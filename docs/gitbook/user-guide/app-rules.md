---
description: Block apps entirely or only while the internet is scheduled off.
---

# App rules

App rules close apps your child should not use. When a blocked app opens, PaCo closes it right away. An app that is already open when a rule arrives is closed within about 10 seconds.

## Rule types

| Type | Behaviour |
|---|---|
| **Always Blocked** | The app is closed every time it opens. |
| **Follows Schedule** | The app is closed only while the chosen schedule has the internet off. When an approved time request turns the internet on, the app is allowed too. |

A **Follows Schedule** rule whose schedule is disabled blocks nothing, just like the schedule. If the schedule is deleted, the rule shows a red warning and the app stays blocked until you delete and re-add the rule.

## Add a rule

1. Open **App Rules** and click **Add Rule**. You need at least one [profile](profiles.md) first.
2. Enter the **App Name**, which is only a label for you, and the app's **Bundle ID**.
3. Choose the **Profile** and the **Type**.
4. For **Follows Schedule**, choose the schedule under **Blocked during**.
5. Click **Add**.

## Finding an app's Bundle ID

The Bundle ID is the app's unique identifier, such as `com.apple.Chess`. On the child's Mac, or any Mac with the app installed, run this in Terminal:

```bash
osascript -e 'id of app "Chess"'
```

Replace `Chess` with the app's name as it appears in the Applications folder.

{% hint style="info" %}
PaCo closes the app without showing the child a message. The child sees the app quit. Notifications are planned for a later version.
{% endhint %}

## Delete a rule

Use the list's delete gesture on the rule's row (swipe left on a trackpad). The change is sent to the child's Mac.
