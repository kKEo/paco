<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Mirrors ScheduleTransfer. `days` holds DayOfWeek raw values (Mon=1 … Sun=7);
        // an overnight window belongs to the day it starts on.
        Schema::create('schedules', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('profile_id')->nullable()->constrained('profiles')->nullOnDelete();
            $table->string('label');
            $table->json('days');
            $table->unsignedTinyInteger('off_hour');
            $table->unsignedTinyInteger('off_minute');
            $table->unsignedTinyInteger('on_hour');
            $table->unsignedTinyInteger('on_minute');
            $table->unsignedTinyInteger('grace_period_minutes')->default(5);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('schedules');
    }
};
