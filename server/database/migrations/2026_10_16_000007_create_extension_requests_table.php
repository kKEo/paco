<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // A child's "more time" request. The id is the child's requestId, so a
        // resend is idempotent and the approval can be correlated on the device.
        Schema::create('extension_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('device_id')->constrained('child_devices')->cascadeOnDelete();
            $table->uuid('profile_id')->nullable();
            $table->string('child_device_name')->nullable(); // self-reported, display only
            $table->unsignedSmallInteger('requested_minutes');
            $table->string('reason', 500)->default('');
            $table->string('status', 20)->default('pending'); // pending|approved|denied|expired|withdrawn
            $table->unsignedSmallInteger('granted_minutes')->nullable();
            $table->timestamp('granted_until')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->foreignId('resolved_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['user_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('extension_requests');
    }
};
