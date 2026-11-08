import 'package:flutter/widgets.dart';

/// Every word the screens show, in English, French and Arabic. The phone's
/// language picks the set; a person who reads none of the three gets English.
///
/// Kept as one small class on purpose: three languages, forty strings, no
/// code generation to explain.
class S {
  const S(this.locale);

  final Locale locale;

  static S of(BuildContext context) => S(Localizations.localeOf(context));

  static const supported = [Locale('en'), Locale('fr'), Locale('ar')];

  String _t(String en, String fr, String ar) => switch (locale.languageCode) {
    'fr' => fr,
    'ar' => ar,
    _ => en,
  };

  // First launch
  String get tagline =>
      _t('Your own tunnel.', 'Votre propre tunnel.', 'سردابك الخاص.');
  String get taglineSub => _t(
    'One server. Your keys. Nobody in between.',
    'Un serveur. Vos clés. Personne entre les deux.',
    'خادم واحد. مفاتيحك أنت. لا أحد في الوسط.',
  );
  String get haveInvite => _t(
    'I was sent an invitation',
    'J\'ai reçu une invitation',
    'وصلتني دعوة',
  );
  String get scanQr =>
      _t('Scan a QR code', 'Scanner un code QR', 'امسح رمز QR');
  String get pasteTitle =>
      _t('Paste the invitation', 'Coller l\'invitation', 'الصق الدعوة');
  String get pasteHint => _t(
    'Copy the message you were sent, then come back here and paste it.',
    'Copiez le message qu\'on vous a envoyé, puis revenez ici et collez-le.',
    'انسخ الرسالة التي أُرسلت إليك، ثم ارجع إلى هنا والصقها.',
  );
  String get pasteField => _t(
    'serdab://add?…  or the config text',
    'serdab://add?…  ou le texte du fichier',
    'serdab://add?…  أو نص الإعدادات',
  );
  String get useIt => _t(
    'Use this invitation',
    'Utiliser cette invitation',
    'استخدم هذه الدعوة',
  );
  String get nothingToPaste => _t(
    'Nothing to paste yet. Copy the message first.',
    'Rien à coller. Copiez d\'abord le message.',
    'لا شيء للصق. انسخ الرسالة أولاً.',
  );
  String notAnInvite(String why) => _t(
    'Not a serdab invitation: $why',
    'Ce n\'est pas une invitation serdab : $why',
    'هذه ليست دعوة سرداب: $why',
  );
  String get onTheServer =>
      _t('on the server:', 'sur le serveur :', 'على الخادم:');
  String get pointAtQr => _t(
    'Point at the QR code the server printed',
    'Visez le code QR affiché par le serveur',
    'وجّه الكاميرا نحو رمز QR الذي أظهره الخادم',
  );

  // The door
  String get shut =>
      _t('The passage is shut.', 'Le passage est fermé.', 'الممر مغلق.');
  String get shutSub => _t(
    'Tap Open to go underground.',
    'Touchez Ouvrir pour descendre.',
    'اضغط افتح للنزول.',
  );
  String get openBtn => _t('Open', 'Ouvrir', 'افتح');
  String get closeBtn => _t('Close', 'Fermer', 'أغلق');
  String get opening =>
      _t('Opening the passage…', 'On ouvre le passage…', 'نفتح الممر…');
  String knocking(String host) =>
      _t('Knocking on $host', 'On frappe chez $host', 'نطرق باب $host');
  String get underground =>
      _t('You are underground.', 'Vous êtes sous terre.', 'أنت في السرداب.');
  String leavesThrough(String label) => _t(
    'Everything leaves through $label.',
    'Tout passe par $label.',
    'كل شيء يمر عبر $label.',
  );
  String get noAnswer => _t(
    'Underground, but no answer.',
    'Sous terre, mais pas de réponse.',
    'في السرداب، لكن لا جواب.',
  );
  String noAnswerSub(String host, String port) => _t(
    'No handshake from $host. Is the server up, is UDP $port open?',
    '$host ne répond pas. Le serveur est-il allumé, le port UDP $port ouvert ?',
    '$host لم يردّ. هل الخادم يعمل، وهل منفذ UDP $port مفتوح؟',
  );
  String get comingUp => _t('Coming back up…', 'On remonte…', 'نصعد…');
  String get denied =>
      _t('The phone said no.', 'Le téléphone a dit non.', 'الهاتف رفض.');
  String get deniedSub => _t(
    'Allow the VPN when the phone asks, then tap again.',
    'Autorisez le VPN quand le téléphone le demande, puis touchez à nouveau.',
    'اسمح بالـ VPN عندما يطلب الهاتف ذلك، ثم اضغط مجدداً.',
  );

  // Numbers under the door
  String get statUnderground => _t('underground', 'sous terre', 'في السرداب');
  String get statDown => _t('down', 'reçu', 'تنزيل');
  String get statUp => _t('up', 'envoyé', 'رفع');
  String get statHandshake => _t('handshake', 'contact', 'مصافحة');
  String ago(int seconds) => seconds < 60
      ? _t('${seconds}s ago', '$seconds s', 'قبل $seconds ث')
      : _t(
          '${seconds ~/ 60}m ago',
          '${seconds ~/ 60} min',
          'قبل ${seconds ~/ 60} د',
        );

  // Device card
  String get stayUnderground =>
      _t('Stay underground', 'Rester sous terre', 'ابقَ في السرداب');
  String get stayUndergroundSub => _t(
    'Never closes by itself, and comes back after a restart.',
    'Ne se ferme jamais seul, et revient après un redémarrage.',
    'لا يُغلق من تلقاء نفسه، ويعود بعد إعادة التشغيل.',
  );
  String get makePermanent => _t(
    'Make it permanent: Android settings',
    'Rendre permanent : réglages Android',
    'اجعله دائماً: إعدادات أندرويد',
  );
  String get makePermanentSub => _t(
    'Settings › VPN › Serdab › Always-on VPN. The phone opens the door itself, seconds after it starts.',
    'Réglages › VPN › Serdab › VPN permanent. Le téléphone ouvre la porte lui-même, quelques secondes après l\'allumage.',
    'الإعدادات › VPN › Serdab › VPN دائم. يفتح الهاتف الباب بنفسه، ثوانٍ بعد تشغيله.',
  );
  String get thisDevice => _t('this device', 'cet appareil', 'هذا الجهاز');
  String get server => _t('server', 'serveur', 'الخادم');
  String get serverKey => _t('server key', 'clé du serveur', 'مفتاح الخادم');
  String get rescan => _t('New invitation', 'Nouveau lien', 'دعوة جديدة');
  String get forget => _t('Forget', 'Oublier', 'انسَ');
  String get callThisServer =>
      _t('Call this server', 'Nommer ce serveur', 'سمِّ هذا الخادم');
  String get cancel => _t('Cancel', 'Annuler', 'إلغاء');
  String get save => _t('Save', 'Enregistrer', 'حفظ');
  String get forgetTitle =>
      _t('Forget this server?', 'Oublier ce serveur ?', 'نسيان هذا الخادم؟');
  String get forgetBody => _t(
    'The key on this phone is deleted. On the server, revoke it too:',
    'La clé de ce téléphone est supprimée. Sur le serveur, révoquez-la aussi :',
    'يُحذف المفتاح من هذا الهاتف. على الخادم، ألغِه أيضاً:',
  );
  String get keep => _t('Keep', 'Garder', 'احتفظ');
  String get ready =>
      _t('This phone is set up.', 'Ce téléphone est prêt.', 'هذا الهاتف جاهز.');

  // Closing by itself
  String closesAt(String time) => _t(
    'Closes by itself at $time',
    'Se ferme tout seul à $time',
    'يُغلق من تلقاء نفسه عند $time',
  );
  String get addHour => _t('+1 hour', '+1 heure', '+ساعة');

  // What the server says about this phone
  String visibleTo(String who) => _t(
    'While you are connected, the sites you visit are visible to $who.',
    'Pendant la connexion, les sites que vous visitez sont visibles par $who.',
    'أثناء الاتصال، المواقع التي تزورها مرئية لـ $who.',
  );
  String accessUntil(String date) => _t(
    'Your access ends on $date.',
    'Votre accès se termine le $date.',
    'ينتهي وصولك في $date.',
  );
  String get accessEnded =>
      _t('Your access has ended', 'Votre accès est terminé', 'انتهى وصولك');
  String get accessEndedSub => _t(
    'Ask the person who invited you for a new invitation.',
    'Demandez une nouvelle invitation à la personne qui vous a invité.',
    'اطلب دعوة جديدة من الشخص الذي دعاك.',
  );

  // Sharing
  String get invite => _t('Invite someone', 'Inviter quelqu\'un', 'ادعُ شخصًا');
  String get inviteName => _t('Their name', 'Son prénom', 'اسمه');
  String get inviteNameHint => _t('e.g. Salma', 'ex. Salma', 'مثلاً سلمى');
  String get createInvite =>
      _t('Create the invitation', 'Créer l\'invitation', 'أنشئ الدعوة');
  String inviteNote(String date) => _t(
    'For one phone. It works until $date. Unused, it expires in 48 hours.',
    'Pour un seul téléphone. Valable jusqu\'au $date. Inutilisée, elle expire dans 48 heures.',
    'لهاتف واحد. صالحة حتى $date. إن لم تُستعمل تنتهي خلال 48 ساعة.',
  );
  String get inviteWarn => _t(
    'It is a key: send it to that one person, then delete the message.',
    'C\'est une clé : envoyez-la à cette seule personne, puis supprimez le message.',
    'إنها مفتاح: أرسلها لذلك الشخص وحده، ثم احذف الرسالة.',
  );
  String get sendIt => _t('Send it', 'L\'envoyer', 'أرسلها');
  String get inviteAgain =>
      _t('Invite someone else', 'Inviter une autre personne', 'ادعُ شخصًا آخر');
  String get yourGuests =>
      _t('People you invited', 'Vos invités', 'الأشخاص الذين دعوتهم');
  String get connectFirst => _t(
    'Open the door first: invitations are made by the server, through the tunnel.',
    'Ouvrez d\'abord la porte : les invitations sont créées par le serveur, via le tunnel.',
    'افتح الباب أولاً: الدعوات يصنعها الخادم عبر السرداب.',
  );
  String guestStatus(String status) => switch (status) {
    'online' => _t('connected', 'connecté', 'متصل'),
    'pending' => _t('not used yet', 'pas encore utilisée', 'لم تُستعمل بعد'),
    'expired' => _t('ended', 'terminée', 'انتهت'),
    'disabled' || 'paused' => _t('stopped', 'arrêtée', 'موقوفة'),
    _ => _t('active', 'active', 'نشطة'),
  };
  String until(String date) =>
      _t('until $date', 'jusqu\'au $date', 'حتى $date');
}
