// Service worker for saved-search alerts ("someone near you is cooking biryani").
self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { title: "ShareYourPot", body: event.data ? event.data.text() : "" };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || "ShareYourPot", {
      body: data.body || "",
      icon: "/icon.svg",
      tag: data.tag,
      data: { url: data.url || "/search" },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/search";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const c of clients) {
        if ("focus" in c && c.url.includes(url)) return c.focus();
      }
      return self.clients.openWindow(url);
    }),
  );
});
