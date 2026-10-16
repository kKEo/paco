<?php

namespace App\Notifications;

use App\Models\ExtensionRequest;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;
use NotificationChannels\WebPush\WebPushChannel;
use NotificationChannels\WebPush\WebPushMessage;

/**
 * A cloud child asks for more time: mail, plus a browser notification on every
 * browser where the parent turned them on (Settings → Notifications).
 */
class ExtensionRequested extends Notification implements ShouldQueue
{
    use Queueable;

    public function __construct(public ExtensionRequest $request) {}

    /** @return list<string> */
    public function via(object $notifiable): array
    {
        $channels = ['mail'];
        if (config('webpush.vapid.public_key') && method_exists($notifiable, 'pushSubscriptions')
            && $notifiable->pushSubscriptions()->exists()) {
            $channels[] = WebPushChannel::class;
        }

        return $channels;
    }

    public function toMail(object $notifiable): MailMessage
    {
        $mail = (new MailMessage)
            ->subject($this->title())
            ->line($this->body());

        return $mail
            ->action('Approve or deny', route('requests.index'))
            ->line('Unanswered requests are denied automatically after '.config('paco.requests.expire_after_hours').' hours.');
    }

    public function toWebPush(object $notifiable, Notification $notification): WebPushMessage
    {
        return (new WebPushMessage)
            ->title($this->title())
            ->body($this->body())
            ->tag('paco-request-'.$this->request->id)
            ->data(['url' => route('requests.index')]);
    }

    private function title(): string
    {
        return "{$this->request->device->name} asks for {$this->request->requested_minutes} more minutes";
    }

    private function body(): string
    {
        return $this->request->reason !== ''
            ? 'Reason: '.$this->request->reason
            : "{$this->request->device->name} is asking for more internet time.";
    }
}
