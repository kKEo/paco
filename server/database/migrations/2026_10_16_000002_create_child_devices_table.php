<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // A cloud-enrolled child Mac. The device authenticates with a bearer token
        // whose secret part is stored only as a SHA-256 hash.
        Schema::create('child_devices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('device_token_hash', 64)->nullable();
            // During a rotation the old token keeps working until the new one is
            // first used, so a lost rotation response cannot lock the Mac out.
            $table->string('previous_token_hash', 64)->nullable();
            $table->timestamp('token_rotated_at')->nullable();
            $table->timestamp('enrolled_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            // Last heartbeat body: internet state, action, overrides (display only).
            $table->json('last_status')->nullable();
            $table->unsignedBigInteger('policy_version')->default(1);
            $table->foreignUuid('active_profile_id')->nullable()->constrained('profiles')->nullOnDelete();
            // Mirror of the manual toggle last sent to the device: {enabled, until}.
            $table->json('manual_override')->nullable();
            $table->string('daemon_version')->nullable();
            // IANA zone the device last reported; its local day is authoritative for usage.
            $table->string('time_zone')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('child_devices');
    }
};
