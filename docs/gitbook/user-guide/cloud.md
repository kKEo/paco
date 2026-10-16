---
description: Manage a child's Mac from a browser, without a second Mac, and follow its screen time from anywhere.
---

# PaCo Cloud

PaCo Cloud is for a parent who has no Mac of their own next to the child's, or who wants to manage it while away from home. The parent uses a web page; the child's Mac talks to a PaCo Cloud server over the internet.

A child's Mac is managed **either** by a parent's Mac on the same network ([Pairing a child's Mac](pairing.md)) **or** by PaCo Cloud, never both at once.

{% hint style="info" %}
PaCo Cloud is a server you run yourself or that someone runs for you: there is no public PaCo service. Setting one up is described in the [PaCo Cloud server](../developer-guide/cloud-server.md) chapter of the Developer Guide.
{% endhint %}

## What you can do from the web page

| Page | What it does |
|---|---|
| **Overview** | Each Mac: online or not, internet on or off, today's app time and internet time, its top apps. |
| **Macs** | Turn the internet on or off for 15 minutes to 4 hours, go back to the schedule, choose which profile a Mac follows, remove a Mac. |
| **Requests** | Approve (with as many minutes as you like) or deny your child's requests for more time. This works even while the child's Mac is offline. |
| **Screen time** | Today, and the last 7 or 30 days: time per app and internet-on time per day. |
| **Activity** | Every command sent to your Macs and whether each Mac has applied it. |
| **Profiles, Schedules, App rules** | The same rules as on a parent's Mac, see [Child profiles](profiles.md), [Internet schedules](schedules.md) and [App rules](app-rules.md). |
| **Parent PIN** | The PIN for “Parent Access” on the child's Mac. |

Changes reach a Mac that is online within a second or two. A Mac that is asleep or off gets them when it is back.

<figure><img src="../.gitbook/assets/dg-cloud.svg" alt="The parent's browser talks to the PaCo Cloud server. The child's Mac sends heartbeats, usage and requests to the server and receives commands through a long-poll."><figcaption><p>The browser, the server and the child’s Mac.</p></figcaption></figure>

## Setting up

1. Sign up on your PaCo Cloud server and confirm your email address.
2. Set a **Parent PIN** (sidebar). You also need it later to change things on the child's Mac itself.
3. Optionally create a profile for your child under **Profiles**, then add schedules and app rules.
4. Choose **Macs → Add a Mac**, pick the profile and click **Create code**. The page shows the server address and an 8-character code, valid for 15 minutes.
5. On the child's Mac, install PaCo and open it. Choose **Set up as Child**, then **PaCo Cloud, from a browser**, and type the server address and the code. On a child's Mac that is already set up and not paired with a parent's Mac, use **Use PaCo Cloud** at the bottom of the PaCo menu instead.

The page notices when the code was used and shows the Mac's name. From then on the Mac follows the rules on the web page.

{% hint style="warning" %}
Set up the child's Mac while its internet is on, or make sure the Mac uses your router for DNS (the usual home setup). Afterwards PaCo keeps the server reachable even while it blocks the internet, so requests and your commands still get through.
{% endhint %}

## On the child's Mac

The PaCo menu looks as described in [On the child's Mac](child-mac.md), with these differences:

* The status line says **Connected to PaCo Cloud**, or **PaCo Cloud not reachable** when the Mac cannot reach the server.
* **Request More Time** sends the request to PaCo Cloud. You get an email, and a browser notification if you turned them on under **Settings → Notifications**.
* **Parent Access** checks the PIN with PaCo Cloud. Five wrong tries lock it for five minutes; you can unlock it early from the **Parent PIN** page.
* After Parent Access, **Settings → PaCo Cloud** shows the connection and has **Disconnect from PaCo Cloud**.

## Removing a Mac

Remove it from the **Macs** page, or disconnect it on the Mac itself as described above. Either way, the Mac stops reporting and taking commands, and **keeps enforcing the rules it has** until it is managed again, by PaCo Cloud or by a parent's Mac.

## Securing your account

Your PaCo Cloud account controls your child's Mac. Use a strong password and turn on **Settings → Two-factor authentication**, which asks for a code from an authenticator app at every login. Removing a Mac and changing the Parent PIN ask for your password again.
