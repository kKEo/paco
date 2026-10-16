// PaCo Cloud service worker: shows request notifications pushed by the server
// and opens the requests page when one is clicked.
self.addEventListener('push', (event) => {
    if (!event.data) return;
    const message = event.data.json();
    event.waitUntil(
        self.registration.showNotification(message.title || 'PaCo Cloud', {
            body: message.body || '',
            tag: message.tag,
            data: message.data || {},
            icon: '/favicon.ico',
        }),
    );
});

self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    const url = (event.notification.data && event.notification.data.url) || '/requests';
    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
            const open = windows.find((w) => w.url.startsWith(self.registration.scope));
            if (open) {
                open.navigate(url);
                return open.focus();
            }
            return clients.openWindow(url);
        }),
    );
});
