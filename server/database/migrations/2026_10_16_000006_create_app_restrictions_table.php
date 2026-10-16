<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Mirrors AppRestrictionTransfer. Deleting the schedule a "Follows Schedule"
        // rule points at nulls the reference on purpose: the daemon then keeps the
        // app blocked and the dashboard flags the rule, like on the Mac.
        Schema::create('app_restrictions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('profile_id')->nullable()->constrained('profiles')->nullOnDelete();
            $table->string('bundle_identifier');
            $table->string('app_name');
            $table->string('restriction_type', 20); // blocked | scheduledOnly
            $table->foreignUuid('allowed_schedule_id')->nullable()->constrained('schedules')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('app_restrictions');
    }
};
