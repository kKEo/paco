<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // One UsageTransfer snapshot per device per *child-local* day (totals only;
        // a newer snapshot for the same day replaces the row).
        Schema::create('usage_days', function (Blueprint $table) {
            $table->id();
            $table->foreignUuid('device_id')->constrained('child_devices')->cascadeOnDelete();
            $table->date('local_date');
            $table->uuid('profile_id')->nullable();
            $table->unsignedInteger('internet_on_seconds')->default(0);
            $table->unsignedInteger('app_seconds')->default(0); // sum of app_entries durations
            $table->json('app_entries');
            $table->timestamp('reported_at');
            $table->timestamps();

            $table->unique(['device_id', 'local_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('usage_days');
    }
};
