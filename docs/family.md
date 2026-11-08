# Setting up someone who does not do computers

The app was built for one test: a parent, a friend, anyone who has never heard
of a VPN, gets a message from you and is underground thirty seconds later,
without reading anything. This is the whole procedure, yours and theirs.

## You, once, on your laptop

```sh
gcloud compute ssh serdab --zone europe-west9-b -- sudo serdab add mom
```

That prints a QR (ignore it, they are not in the room) and one long line that
starts with `serdab://add?c=`. That line **is their private key**. Send it to
that one person, in a chat you trust (WhatsApp, Signal, iMessage), and delete
the message once they are in. `serdab link mom` prints it again.

Then get the app onto their phone. Honest picture:

| Phone | What works | What does not |
|---|---|---|
| Android | the release APK from `flutter build apk --release`, sent in the same chat or hosted in a GitHub release. The phone asks once to "allow installing from this source". Do it with them on a call, or before you hand the phone back. | The Play Store, until you publish it there. |
| iPhone | TestFlight: upload once from Xcode (Product → Archive → Distribute → TestFlight), add their Apple ID as a tester, they get an email with an "Install" button. | Sending an app file. iPhones only install from the App Store or TestFlight. |

## Them, once, on their phone

1. Open the message. Tap the link if it is blue. If it is not blue (WhatsApp on
   Android does not always make `serdab://` links tappable), **hold the
   message, Copy**, then open Serdab and tap **"I was sent an invitation"**.
   The app reads the clipboard and sets itself up. Nothing to type.
2. The phone asks once: *"Serdab wants to set up a VPN connection"*. **OK /
   Allow.** On iPhone it then asks for the passcode or Face ID. That is Apple
   installing the VPN profile; it happens exactly once.
3. The door lights up. **"You are underground."** Done.

## Them, every day after

Nothing. **"Stay underground"** is on by default, so:

- On **iPhone**, the system itself raises the tunnel whenever there is any
  network, including after a restart. The app does not even need to be open.
- On **Android**, the app reopens the door when it is launched. After a
  restart it also comes back on its own, but Android 13 and later hand the
  "phone restarted" signal to apps late (minutes, sometimes twenty). The way
  to make it immediate is the phone's own setting, once: in the app tap
  **"Make it permanent: Android settings"**, then *Serdab ⚙ → Always-on VPN*.
  The system then starts the tunnel itself seconds after power-on; *Block
  connections without VPN* on the same page is a real kill switch.

If they ever tap the door to come back up, the next time they open the app it
goes back underground by itself. The only way to keep it off is the switch
under the door.

## When something is off

- **"Underground, but no answer."** The phone is in the tunnel but Paris never
  shook hands: the server is down, or UDP 51820 is blocked where they are
  (some hotel and office Wi-Fi). Check `sudo serdab list` on the server; their
  row says `never` or a time.
- **The link does nothing.** The app is not installed yet, or the message got
  mangled. `serdab link <device>` prints a fresh copy; the app also accepts the
  plain config text from `serdab conf <device>` pasted the same way.
- **Someone's phone is lost.** `sudo serdab rm <device>`. That key can never
  connect again; `serdab add` again for the new phone.

## What to tell them, in their words

The app speaks English, French and Arabic, following the phone's language.
Paste one of these with the link:

> **FR** — Clique sur le lien (ou copie le message, ouvre Serdab et appuie sur
> « J'ai reçu une invitation »). Dis « Autoriser » quand le téléphone demande.
> Quand la porte s'allume, c'est bon. Tu n'as plus rien à faire après.

> **AR** — اضغط على الرابط (أو انسخ الرسالة، افتح سرداب واضغط «وصلتني دعوة»).
> قل «موافق» عندما يطلب الهاتف. عندما يضيء الباب، انتهى الأمر. لا شيء آخر بعد ذلك.
