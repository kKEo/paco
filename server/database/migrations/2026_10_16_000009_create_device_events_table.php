<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Outbox of commands for a device (long-poll) and, kept for 90 days, the
        // audit log of what was sent. The auto-increment id is the poll cursor.
        Schema::create('device_events', function (Blueprint $table) {
            $table->id();
            $table->foreignUuid('device_id')->constrained('child_devices')->cascadeOnDelete();
            $table->string('type', 40);
            $table->json('payload');
            $table->foreignId('actor_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamp('acked_at')->nullable();
            $table->timestamp('created_at')->nullable();

            $table->index(['device_id', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_events');
    }
};
