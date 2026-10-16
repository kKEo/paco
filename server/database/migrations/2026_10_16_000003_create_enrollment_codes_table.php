<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // One-time enrollment codes (8 Crockford base32 chars, ~40 bits), short-lived
        // and single use. Stored in clear so the enrollment page can re-show it.
        Schema::create('enrollment_codes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('code', 8)->index();
            $table->string('device_name_hint')->nullable();
            $table->foreignUuid('active_profile_id')->nullable()->constrained('profiles')->nullOnDelete();
            $table->timestamp('expires_at');
            $table->timestamp('used_at')->nullable();
            $table->foreignUuid('used_by_device_id')->nullable()->constrained('child_devices')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('enrollment_codes');
    }
};
