<?php

namespace Tests\Feature;

use App\Services\FirebaseService;
use Kreait\Firebase\JWT\Error\IdTokenVerificationFailed;
use Mockery;
use Tests\TestCase;

class FirebaseAuthEndpointTest extends TestCase
{
    public function test_profile_endpoint_requires_a_bearer_token(): void
    {
        $this->getJson('/api/me')
            ->assertUnauthorized()
            ->assertJsonPath('code', 'unauthenticated');
    }

    public function test_profile_endpoint_returns_the_authenticated_users_profile(): void
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('isConfigured')->once()->andReturn(true);
        $firebase->shouldReceive('verifyIdToken')
            ->once()
            ->with('valid-token')
            ->andReturn(['sub' => 'user-123']);
        $firebase->shouldReceive('getUserProfile')
            ->once()
            ->with('user-123')
            ->andReturn([
                'uid' => 'user-123',
                'name' => 'Bunda',
                'email' => 'bunda@example.test',
                'role' => 'patient',
                'verified' => true,
                'created_at' => '2026-01-01T00:00:00+00:00',
            ]);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->getJson('/api/me')
            ->assertOk()
            ->assertJsonPath('data.uid', 'user-123')
            ->assertJsonPath('data.role', 'patient');
    }

    public function test_registration_sets_midwife_applications_to_pending_server_side(): void
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('isConfigured')->once()->andReturn(true);
        $firebase->shouldReceive('verifyIdToken')
            ->once()
            ->with('valid-token')
            ->andReturn([
                'sub' => 'midwife-123',
                'email' => 'midwife@example.test',
            ]);
        $firebase->shouldReceive('createUserProfile')
            ->once()
            ->with('midwife-123', Mockery::on(static function (array $profile): bool {
                return $profile['role'] === 'midwife'
                    && $profile['verified'] === false
                    && $profile['str_number'] === 'STR-123';
            }))
            ->andReturn(true);
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('valid-token')
            ->postJson('/api/auth/register', [
                'name' => 'Bidan',
                'role' => 'midwife',
                'credential_label' => 'Bidan',
                'str_number' => 'STR-123',
                'verified' => true,
            ])
            ->assertCreated()
            ->assertJsonPath('data.role', 'midwife')
            ->assertJsonPath('data.verified', false)
            ->assertJsonMissingPath('data.str_number');
    }

    public function test_invalid_firebase_id_token_is_rejected(): void
    {
        $firebase = Mockery::mock(FirebaseService::class);
        $firebase->shouldReceive('isConfigured')->once()->andReturn(true);
        $firebase->shouldReceive('verifyIdToken')
            ->once()
            ->with('invalid-token')
            ->andThrow(new IdTokenVerificationFailed('Invalid token.'));
        $this->app->instance(FirebaseService::class, $firebase);

        $this->withToken('invalid-token')
            ->getJson('/api/me')
            ->assertUnauthorized()
            ->assertJsonPath('code', 'unauthenticated');
    }
}
