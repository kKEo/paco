<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Http\Requests\Device\EventsRequest;
use App\Models\DeviceEvent;
use App\Services\Devices\LongPoll;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Long-poll for commands. The cursor the device sends is the id of the last
 * event it applied, which also acknowledges everything up to it.
 */
class EventsController extends Controller
{
    public function index(EventsRequest $request, LongPoll $poll): JsonResponse
    {
        $device = $request->device();
        $cursor = (int) $request->validated('cursor', 0);
        $wait = (int) $request->validated('wait', config('paco.longpoll.max_seconds'));

        // The hold plus processing must fit; PHP's default limit is 30 s.
        @set_time_limit(config('paco.longpoll.max_seconds') + 15);

        $poll->ack($device, $cursor);
        $result = $poll->fetch($device, $cursor, $wait);
        $events = $result['events'];

        return response()->json(array_filter([
            'events' => $events->map(fn (DeviceEvent $e) => $e->toWire())->values()->all(),
            'nextCursor' => $events->isEmpty() ? $cursor : max($cursor, (int) $events->last()->id),
            'serverTime' => Iso::now(),
            'retryAfter' => $result['retryAfter'],
        ], fn ($v) => $v !== null));
    }

    public function ack(Request $request, LongPoll $poll): JsonResponse
    {
        $data = $request->validate(['cursor' => ['required', 'integer', 'min:0']]);
        $poll->ack($request->user(), (int) $data['cursor']);

        return response()->json(['acked' => (int) $data['cursor']]);
    }
}
