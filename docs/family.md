# Setting up someone who does not do computers

The app was built for one test: a parent, a friend, anyone who has never heard
of a VPN, gets a message from you and is through thirty seconds later, without
reading anything. This is the whole procedure, yours and theirs.

## You, once

1. **Make the invitation.** In the app: **Invite someone**, type their name,
   **Create the invitation**, **Send it**. Or in the console: **New invitation**
   (pick `family`, `kid` or `guest`). Or on the server:
   `sudo serdab add mom family`.
2. **Send it** in a chat you trust (WhatsApp, Signal, iMessage). It is a normal
   blue `https://…/join#…` link. It **is their private key**: send it to that
   one person, and delete the message once they are in.
3. **Get the app onto their phone.** Honest picture:

| Phone | What works | What does not |
|---|---|---|
| Android | the release APK from `flutter build apk --release`, sent in the same chat. The phone asks once to "allow installing from this source". Do it with them on a call, or before you hand the phone back. | The Play Store, until it is published there. |
| iPhone | TestFlight: upload once from Xcode (Product → Archive → Distribute → TestFlight), add their Apple ID as a tester, they get an email with an "Install" button. Or plug their phone into your Mac and build to it. | Sending an app file. iPhones only install from the App Store, TestFlight or Xcode. |

## Them, once

1. **Tap the link**, then **Open in Serdab**. The app sets itself up. (If the
   button does nothing: copy the message, open Serdab, tap **"I was sent an
   invitation"**.)
2. The phone asks once: *"Serdab wants to set up a VPN connection"*. **OK /
   Allow.** On iPhone it then asks for the passcode or Face ID; that is Apple
   installing the VPN profile, and it happens exactly once.
3. The door lights up: **"You are underground."** Done.

## Them, every day after

**Open the app.** That opens the tunnel, no tap needed. It closes by itself two
hours later. In the last ten minutes a notification says *"Serdab closes in 10
minutes"* with **Renew 1 hour**, for a call that runs long. When it closes,
another notification says so. The **Close** button under the door closes it
earlier.

Owner and family devices can turn on **Stay underground** instead: the tunnel
never closes by itself. On Android, make it truly permanent from the phone's
own *Settings › VPN › Serdab ⚙ › Always-on VPN* (the app has a shortcut).

## When something is off

- **"Another VPN is in the way."** (Android) Another VPN app, ExpressVPN for
  example, is set to *Always-on*. Android lets only one app hold that, and no
  app may switch another off. Tap **Open VPN settings**, tap the other app's
  gear, turn *Always-on VPN* off, come back: Serdab opens by itself.
- **"Underground, but no answer."** The phone is in the tunnel but the server
  never answered: the server is down, or WireGuard's UDP port is blocked where
  they are (some hotel and office Wi-Fi). On the server, `sudo serdab list`
  shows their last contact.
- **"Your access has ended."** A guest's three weeks are over. They ask you,
  or whoever invited them, for a new invitation.
- **The link does nothing.** The app is not installed yet. Install it, then tap
  the link again.
- **A phone is lost.** Revoke it in the console, or `sudo serdab rm <device>`.
  That key can never connect again; invite the new phone.

## What to tell them, in their words

The app speaks English, French and Arabic, following the phone's language.
Paste one of these with the link:

> **EN** — Tap the link, then "Open in Serdab". Say "Allow" when the phone
> asks. When the door lights up, you are done. Next time, just open the app.

> **FR** — Touche le lien, puis « Ouvrir dans Serdab ». Dis « Autoriser » quand
> le téléphone demande. Quand la porte s'allume, c'est bon. La prochaine fois,
> ouvre simplement l'app.

> **AR** — اضغط على الرابط ثم «افتح في سرداب». قل «موافق» عندما يطلب الهاتف.
> عندما يضيء الباب، انتهى الأمر. في المرة القادمة افتح التطبيق فقط.
