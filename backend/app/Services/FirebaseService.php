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
                $this->documentsUrl().'/users?documentId='.rawurlencode($uid),
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
            ->connectTimeout(3)
            ->timeout(15)
            ->get($this->documentsUrl().'/users/'.rawurlencode($uid));

        if ($response->status() === 404) {
            return null;
        }

        $response->throw();

        return $this->decodeFields($response->json('fields', []));
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function getActiveVerifiedMidwives(): array
    {
        return $this->runFirestoreQuery('midwives', [
            ['field' => 'active', 'value' => ['booleanValue' => true]],
            ['field' => 'verification_status', 'value' => ['stringValue' => 'verified']],
        ]);
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function getAvailableSlots(string $midwifeId): array
    {
        return $this->runFirestoreQuery('slots', [
            ['field' => 'midwife_id', 'value' => ['stringValue' => $midwifeId]],
            ['field' => 'status', 'value' => ['stringValue' => 'available']],
            ['field' => 'start_at', 'operator' => 'GREATER_THAN', 'value' => [
                'timestampValue' => now()->toIso8601String(),
            ]],
        ]);
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

    /**
     * @param  list<array{field: string, value: array<string, mixed>, operator?: string}>  $filters
     * @return list<array<string, mixed>>
     */
    private function runFirestoreQuery(string $collection, array $filters): array
    {
        $structuredFilters = array_map(
            static fn (array $filter): array => [
                'fieldFilter' => [
                    'field' => ['fieldPath' => $filter['field']],
                    'op' => $filter['operator'] ?? 'EQUAL',
                    'value' => $filter['value'],
                ],
            ],
            $filters,
        );

        $response = Http::withToken($this->firestoreAccessToken())
            ->acceptJson()
            ->connectTimeout(3)
            ->timeout(15)
            ->post($this->documentsUrl().':runQuery', [
                'structuredQuery' => [
                    'from' => [['collectionId' => $collection]],
                    'where' => [
                        'compositeFilter' => [
                            'op' => 'AND',
                            'filters' => $structuredFilters,
                        ],
                    ],
                    'limit' => 100,
                ],
            ]);

        $response->throw();

        $rows = $response->json();
        if (! is_array($rows)) {
            throw new RuntimeException('Firestore returned an invalid query response.');
        }

        $documents = [];
        foreach ($rows as $row) {
            if (! is_array($row) || ! is_array($row['document'] ?? null)) {
                continue;
            }

            $document = $row['document'];
            $fields = $this->decodeFields(is_array($document['fields'] ?? null) ? $document['fields'] : []);
            $name = $document['name'] ?? null;

            if (is_string($name)) {
                $fields['id'] = basename($name);
            }

            $documents[] = $fields;
        }

        return $documents;
    }

    private function documentsUrl(): string
    {
        $projectId = $this->projectId();

        if ($projectId === null) {
            throw new RuntimeException('FIREBASE_PROJECT_ID is not configured.');
        }

        return 'https://firestore.googleapis.com/v1/projects/'
            .$projectId.'/databases/(default)/documents';
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
            if (is_array($field)) {
                $decoded[$name] = $this->decodeValue($field);
            }
        }

        return $decoded;
    }

    /**
     * @param  array<string, mixed>  $value
     */
    private function decodeValue(array $value): mixed
    {
        foreach ([
            'stringValue',
            'booleanValue',
            'timestampValue',
            'integerValue',
            'doubleValue',
            'nullValue',
            'referenceValue',
        ] as $type) {
            if (array_key_exists($type, $value)) {
                return $type === 'integerValue' ? (int) $value[$type] : $value[$type];
            }
        }

        if (is_array($value['mapValue']['fields'] ?? null)) {
            return $this->decodeFields($value['mapValue']['fields']);
        }

        if (is_array($value['arrayValue']['values'] ?? null)) {
            return array_map(
                fn (mixed $item): mixed => is_array($item) ? $this->decodeValue($item) : null,
                $value['arrayValue']['values'],
            );
        }

        return null;
    }
}
