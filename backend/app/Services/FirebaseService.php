<?php

namespace App\Services;

use Google\Auth\Credentials\ServiceAccountCredentials;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Kreait\Firebase\JWT\IdTokenVerifier;
use RuntimeException;

class FirebaseService
{
    /**
     * @var array<string, IdTokenVerifier>
     */
    private static array $idTokenVerifiers = [];

    public function isConfigured(): bool
    {
        return $this->projectId() !== null && is_file($this->credentialsPath());
    }

    /**
     * @return array<string, mixed>
     */
    public function verifyIdToken(string $token): array
    {
        return $this->idTokenVerifier()->verifyIdToken($token)->payload();
    }

    /**
     * @param  array<string, string|bool>  $profile
     */
    public function createUserProfile(string $uid, array $profile): bool
    {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->timeout(15)
            ->post(
                $this->usersCollectionUrl().'?documentId='.rawurlencode($uid),
                ['fields' => $this->encodeFields($profile)],
            );

        if ($response->status() === 409) {
            return false;
        }

        $response->throw();

        return true;
    }

    /**
     * @return array<string, mixed>|null
     */
    public function getUserProfile(string $uid): ?array
    {
        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->timeout(15)
            ->get($this->usersCollectionUrl().'/'.rawurlencode($uid));

        if ($response->status() === 404) {
            return null;
        }

        $response->throw();

        return $this->decodeFields($response->json('fields', []));
    }

    private function idTokenVerifier(): IdTokenVerifier
    {
        $projectId = $this->projectId();

        if ($projectId === null) {
            throw new RuntimeException('FIREBASE_PROJECT_ID is not configured.');
        }

        return self::$idTokenVerifiers[$projectId]
            ??= IdTokenVerifier::createWithProjectId($projectId);
    }

    private function projectId(): ?string
    {
        $projectId = config('firebase.project_id');

        return is_string($projectId) && $projectId !== '' ? $projectId : null;
    }

    private function credentialsPath(): string
    {
        $path = (string) config('firebase.credentials');

        if (
            str_starts_with($path, '/')
            || str_starts_with($path, '\\')
            || preg_match('/^[A-Za-z]:[\/\\\\]/', $path) === 1
        ) {
            return $path;
        }

        return base_path($path);
    }

    private function firestoreAccessToken(): string
    {
        $projectId = $this->projectId();
        $credentialsPath = $this->credentialsPath();

        if ($projectId === null || ! is_file($credentialsPath)) {
            throw new RuntimeException('Firebase service-account credentials are not configured.');
        }

        $cacheKey = 'firebase.firestore.access_token.'.$projectId;
        $cache = Cache::store('file');
        $cachedToken = $cache->get($cacheKey);

        if (is_string($cachedToken)) {
            return $cachedToken;
        }

        $credentials = new ServiceAccountCredentials(
            'https://www.googleapis.com/auth/datastore',
            $credentialsPath,
        );
        $tokenResponse = $credentials->fetchAuthToken();
        $accessToken = $tokenResponse['access_token'] ?? null;

        if (! is_string($accessToken) || $accessToken === '') {
            throw new RuntimeException('Google Auth did not return a Firestore access token.');
        }

        $expiresIn = max(60, (int) ($tokenResponse['expires_in'] ?? 3600) - 60);
        $cache->put($cacheKey, $accessToken, now()->addSeconds($expiresIn));

        return $accessToken;
    }

    private function usersCollectionUrl(): string
    {
        $projectId = $this->projectId();

        if ($projectId === null) {
            throw new RuntimeException('FIREBASE_PROJECT_ID is not configured.');
        }

        return 'https://firestore.googleapis.com/v1/projects/'
            .$projectId.'/databases/(default)/documents/users';
    }

    /**
     * @param  array<string, string|bool>  $fields
     * @return array<string, array{stringValue?: string, booleanValue?: bool}>
     */
    private function encodeFields(array $fields): array
    {
        $encoded = [];

        foreach ($fields as $name => $value) {
            $encoded[$name] = is_bool($value)
                ? ['booleanValue' => $value]
                : ['stringValue' => $value];
        }

        return $encoded;
    }

    /**
     * @param  array<string, mixed>  $fields
     * @return array<string, mixed>
     */
    private function decodeFields(array $fields): array
    {
        $decoded = [];

        foreach ($fields as $name => $field) {
            if (! is_array($field)) {
                continue;
            }

            foreach (['stringValue', 'booleanValue', 'timestampValue', 'integerValue'] as $type) {
                if (array_key_exists($type, $field)) {
                    $decoded[$name] = $field[$type];
                    break;
                }
            }
        }

        return $decoded;
    }
}
