<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

class GeminiService
{
    private const SYSTEM_PROMPT = <<<'PROMPT'
Kamu adalah TeleBunda AI, asisten edukasi kesehatan maternal dan kehamilan yang ramah, hangat, dan empatik untuk ibu hamil dan keluarga di Indonesia.

ATURAN KESELAMATAN MUTLAK:
1. Kamu BUKAN dokter dan TIDAK memberikan diagnosis klinis atau meresepkan obat keras. Jawabanmu hanya edukasi awal dan tidak menggantikan pemeriksaan langsung.
2. Jika pengguna menyebut tanda bahaya kehamilan seperti perdarahan, ketuban pecah atau rembes sebelum waktunya, kejang, nyeri kepala hebat dengan pandangan kabur, gerakan janin berkurang drastis atau tidak bergerak, nyeri dada, sesak napas berat, atau demam tinggi, wajib arahkan pengguna segera ke IGD atau fasilitas kesehatan terdekat. Jangan menenangkan pengguna secara berlebihan atau menyarankan menunggu.
3. Selalu sarankan konsultasi langsung dengan bidan atau dokter Sp.OG untuk pemeriksaan fisik dan USG bila keluhan membutuhkan penilaian klinis.
4. Gunakan Bahasa Indonesia yang santun, menenangkan, mudah dipahami, dan berbasis edukasi kesehatan ibu dan anak.
5. Jangan mengaku telah memeriksa pasien, melihat hasil laboratorium/USG, atau mengetahui kondisi yang tidak diberikan pengguna.
PROMPT;

    public function isConfigured(): bool
    {
        $apiKey = config('services.gemini.api_key');

        return is_string($apiKey) && $apiKey !== '';
    }

    /**
     * @param  list<array{role: string, text: string}>  $history
     * @return array{status: 'ok', text: string}|array{status: 'error', code: string}
     */
    public function generateResponse(string $message, array $history = []): array
    {
        $apiKey = config('services.gemini.api_key');
        $model = config('services.gemini.model', 'gemini-3.5-flash-lite');

        if (! is_string($apiKey) || $apiKey === '' || ! is_string($model) || $model === '') {
            return ['status' => 'error', 'code' => 'gemini_not_configured'];
        }

        $contents = [];
        foreach (array_slice($history, -12) as $turn) {
            if (
                is_array($turn)
                && in_array($turn['role'] ?? null, ['user', 'model'], true)
                && is_string($turn['text'] ?? null)
                && trim($turn['text']) !== ''
            ) {
                $contents[] = [
                    'role' => $turn['role'],
                    'parts' => [['text' => $turn['text']]],
                ];
            }
        }
        $contents[] = [
            'role' => 'user',
            'parts' => [['text' => $message]],
        ];

        try {
            $response = Http::acceptJson()
                ->asJson()
                ->connectTimeout(15)
                ->timeout(30)
                ->withHeaders(['x-goog-api-key' => $apiKey])
                ->post(
                    'https://generativelanguage.googleapis.com/v1beta/models/'
                        .rawurlencode($model).':generateContent',
                    [
                        'systemInstruction' => [
                            'parts' => [['text' => self::SYSTEM_PROMPT]],
                        ],
                        'contents' => $contents,
                        'generationConfig' => [
                            'temperature' => 0.2,
                            'maxOutputTokens' => 600,
                        ],
                    ],
                );
        } catch (ConnectionException) {
            return ['status' => 'error', 'code' => 'gemini_unavailable'];
        }

        if ($response->failed()) {
            return ['status' => 'error', 'code' => 'gemini_provider_error'];
        }

        $text = $response->json('candidates.0.content.parts.0.text');
        if (! is_string($text) || trim($text) === '') {
            return ['status' => 'error', 'code' => 'gemini_empty_response'];
        }

        return ['status' => 'ok', 'text' => trim($text)];
    }
}
