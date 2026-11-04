<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\GeminiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AiChatController extends Controller
{
    public function store(Request $request, GeminiService $gemini): JsonResponse
    {
        $data = $request->validate([
            'message' => ['required', 'string', 'max:2000'],
            'history' => ['sometimes', 'array', 'max:12'],
            'history.*.role' => ['required', 'in:user,model'],
            'history.*.text' => ['required', 'string', 'max:2000'],
        ]);

        $result = $gemini->generateResponse(
            trim($data['message']),
            $data['history'] ?? [],
        );

        if ($result['status'] !== 'ok') {
            $status = $result['code'] === 'gemini_not_configured' ? 503 : 502;

            return response()->json([
                'message' => 'Asisten AI sementara tidak dapat menjawab. Silakan coba lagi atau hubungi bidan.',
                'code' => $result['code'],
            ], $status);
        }

        return response()->json(['data' => ['reply' => $result['text']]]);
    }
}
