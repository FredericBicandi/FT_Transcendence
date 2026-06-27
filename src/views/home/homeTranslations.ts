export type HomeLanguage = "english" | "french" | "arabic";

export type LegalSection = {
  title: string;
  body: string;
};

// Keep all dashboard copy in one place so language switches do not touch UI logic.
export type HomeTranslations = {
  auth: {
    authFailed: string;
    close: string;
    code: string;
    codeRequired: string;
    codeSent: string;
    connectVia: string;
    email: string;
    emailRequired: string;
    sendCode: string;
    sendingCode: string;
    verifyCode: string;
    verifyingCode: string;
  };
  chat: {
    close: string;
    cooldown: string;
    inputLabel: string;
    open: string;
    placeholder: string;
    signInToSend: string;
    title: string;
    unavailable: string;
  };
  fullscreen: {
    enter: string;
    exit: string;
  };
  home: {
    battleArena: string;
    loginSignup: string;
    loading: string;
    online: string;
    play: string;
  };
  language: {
    label: string;
    options: Record<HomeLanguage, string>;
  };
  legal: {
    close: string;
    lastUpdated: string;
    privacyPolicy: string;
    privacySections: LegalSection[];
    termsOfService: string;
    termsSections: LegalSection[];
  };
  profile: {
    apply: string;
    applying: string;
    chooseUsername: string;
    close: string;
    confirm: string;
    dateTime: string;
    deleteAccount: string;
    deleteAccountConfirm: string;
    deletingAccount: string;
    death: string;
    exp: string;
    imageRequired: string;
    kills: string;
    level: string;
    logout: string;
    matchLog: string;
    noMatchLogs: string;
    photoInput: string;
    playTime: string;
    profile: string;
    saveFailed: string;
    saveSuccess: string;
    score: string;
    signInToSaveMatchLogs: string;
    usernameTaken: string;
    usernameRequired: string;
    usernameInput: string;
  };
};

export const homeTranslations: Record<HomeLanguage, HomeTranslations> = {
  english: {
    auth: {
      authFailed: "Could not complete email login",
      close: "Close login popup",
      code: "Code",
      codeRequired: "Enter the verification code",
      codeSent: "Verification code sent",
      connectVia: "Or Connect Via",
      email: "email",
      emailRequired: "Enter your email",
      sendCode: "Send Code",
      sendingCode: "Sending...",
      verifyCode: "Verify Code",
      verifyingCode: "Verifying...",
    },
    chat: {
      close: "Close global chat",
      cooldown: "Wait {seconds}s",
      inputLabel: "Global chat message",
      open: "Chat",
      placeholder: "Type message...",
      signInToSend: "Sign in to chat",
      title: "Global Chat",
      unavailable: "Chat unavailable",
    },
    fullscreen: {
      enter: "Fullscreen",
      exit: "Exit",
    },
    home: {
      battleArena: "Battle Arena",
      loginSignup: "Login / Sign Up",
      loading: "Loading...",
      online: "online",
      play: "Play",
    },
    language: {
      label: "Language",
      options: {
        english: "English",
        french: "French",
        arabic: "Arabic",
      },
    },
    legal: {
      close: "Close legal notice",
      lastUpdated: "Last updated: June 27, 2026",
      privacyPolicy: "Privacy Policy",
      privacySections: [
        {
          title: "1. About this policy",
          body: "This policy explains how Pixel Fight, an educational multiplayer game created for the 42 curriculum, handles personal data when you use the dashboard, account features, global chat, and online matches.",
        },
        {
          title: "2. Data we collect",
          body: "If you create an account, we process your email address, authentication provider identifier, player ID, username, and optional avatar. We also store progression and match information such as level, XP, score, kills, deaths, play time, and match dates. Global chat messages and online presence are processed in real time. Guests receive a locally generated profile stored in their browser. Our hosting and network providers may also process standard technical data such as IP address, browser information, timestamps, and error logs.",
        },
        {
          title: "3. How we use data",
          body: "We use this data to authenticate players, operate multiplayer sessions and chat, display profiles and leaderboards, save progression and match history, prevent abuse, maintain security, diagnose faults, and improve the service. We do not sell personal data or use it for targeted advertising.",
        },
        {
          title: "4. Storage and service providers",
          body: "Account, profile, and match data are stored through Supabase. Google or GitHub process information when you choose their OAuth sign-in option. The multiplayer server temporarily processes live game, presence, and chat events. These providers handle data under their own terms and privacy notices.",
        },
        {
          title: "5. Browser storage",
          body: "Pixel Fight uses browser local storage for your selected language, guest profile, and limited profile caching. Supabase may use cookies or similar browser storage to maintain an authenticated session. You can clear this data through your browser, but doing so may sign you out or reset guest progress.",
        },
        {
          title: "6. Retention",
          body: "Account and saved gameplay data are kept while your account remains active and as needed to operate or secure the service. Live chat and transient game events are not intended as permanent records. Technical logs may be retained for a limited troubleshooting and security period. Data may remain briefly in backups after deletion.",
        },
        {
          title: "7. Your choices and rights",
          body: "You can update your username and avatar or delete your account from the Profile window. Account deletion removes the account and associated saved Pixel Fight data from active systems, subject to short-lived backups and records required for security or legal compliance. Depending on your location, you may also have rights to access, correct, erase, restrict, or export personal data.",
        },
        {
          title: "8. Safety and children",
          body: "We use reasonable technical and organizational safeguards, but no online service can guarantee absolute security. Do not share sensitive personal information in your username or global chat. Pixel Fight is not directed to children under 13, or below the minimum digital-consent age required in their country, and we do not knowingly collect their data.",
        },
        {
          title: "9. Changes and contact",
          body: "We may update this policy when the project or its data practices change. The date above identifies the current version. Privacy questions or requests can be submitted to the Pixel Fight maintainers through the FT_Transcendence project repository.",
        },
      ],
      termsOfService: "Terms of Service",
      termsSections: [
        {
          title: "1. Acceptance",
          body: "By accessing or using Pixel Fight, you agree to these Terms of Service and the Privacy Policy. If you do not agree, do not use the service. Pixel Fight is an educational project created for the 42 curriculum, not a commercial gaming service.",
        },
        {
          title: "2. Accounts",
          body: "You may play as a guest or sign in using an available email or OAuth provider. You are responsible for activity under your account and for keeping access to your email and provider accounts secure. Provide an appropriate username and avatar, and do not impersonate another person.",
        },
        {
          title: "3. Fair play and conduct",
          body: "Do not cheat, exploit bugs, automate play, interfere with servers, evade security controls, harass others, or post unlawful, hateful, threatening, sexually explicit, deceptive, or privacy-invasive content. Do not upload malicious files or use chat to spam or advertise. We may restrict access or remove content or accounts that violate these rules.",
        },
        {
          title: "4. Your content",
          body: "You retain responsibility for usernames, avatars, and chat messages you submit. You grant Pixel Fight the limited permission needed to host, process, and display that content to operate the service. Only submit content you have the right to use.",
        },
        {
          title: "5. Project license",
          body: "The game, dashboard, artwork, code, and other project materials are protected by applicable intellectual-property rights and the licenses identified in the project repository. These terms do not transfer ownership or grant rights beyond using the service and any rights expressly provided by those licenses.",
        },
        {
          title: "6. Availability and changes",
          body: "The service is provided for learning and demonstration. Features, game balance, accounts, stored progress, and availability may change, be reset, or be discontinued. Maintenance, faults, or third-party services may interrupt access. We do not promise uninterrupted operation or permanent storage of gameplay data.",
        },
        {
          title: "7. Disclaimer and liability",
          body: "To the extent permitted by law, Pixel Fight is provided “as is” and “as available,” without warranties of merchantability, fitness for a particular purpose, or non-infringement. The maintainers are not liable for indirect, incidental, special, consequential, or data-loss damages arising from use of the service. Rights that cannot legally be excluded remain unaffected.",
        },
        {
          title: "8. Termination",
          body: "You may stop using Pixel Fight at any time and may delete an authenticated account from the Profile window. We may suspend or terminate access when reasonably necessary for security, service integrity, legal compliance, or a violation of these terms.",
        },
        {
          title: "9. Updates and contact",
          body: "We may revise these terms as the project changes. Continued use after an update means you accept the revised terms. The date above identifies the current version. Questions can be submitted to the Pixel Fight maintainers through the FT_Transcendence project repository.",
        },
      ],
    },
    profile: {
      apply: "Apply",
      applying: "Applying...",
      chooseUsername: "Choose your username",
      close: "Close profile popup",
      confirm: "Confirm",
      dateTime: "Date / Time",
      deleteAccount: "Delete account",
      deleteAccountConfirm:
        "Delete your account and all saved Pixel Fight data?",
      deletingAccount: "Deleting...",
      death: "Death",
      exp: "Exp",
      imageRequired: "Choose a PNG, JPG, GIF, or WEBP image",
      kills: "Kills",
      level: "Level",
      logout: "Logout",
      matchLog: "Match Log",
      noMatchLogs: "No match logs yet",
      photoInput: "Choose profile photo",
      playTime: "Play Time",
      profile: "Profile",
      saveFailed: "Could not save profile",
      saveSuccess: "Profile saved",
      score: "Score",
      signInToSaveMatchLogs: "Sign in to save match logs",
      usernameTaken: "Username already taken",
      usernameRequired: "Enter a username",
      usernameInput: "Player username",
    },
  },
  french: {
    auth: {
      authFailed: "Connexion email impossible",
      close: "Fermer la fenetre de connexion",
      code: "Code",
      codeRequired: "Entrez le code",
      codeSent: "Code envoye",
      connectVia: "Ou Connectez-Vous Via",
      email: "email",
      emailRequired: "Entrez votre email",
      sendCode: "Envoyer Code",
      sendingCode: "Envoi...",
      verifyCode: "Verifier Code",
      verifyingCode: "Verification...",
    },
    chat: {
      close: "Fermer le chat global",
      cooldown: "Attendez {seconds}s",
      inputLabel: "Message du chat global",
      open: "Chat",
      placeholder: "Ecrire un message...",
      signInToSend: "Connectez-vous pour chatter",
      title: "Chat Global",
      unavailable: "Chat indisponible",
    },
    fullscreen: {
      enter: "Plein",
      exit: "Quitter",
    },
    home: {
      battleArena: "Arene de Combat",
      loginSignup: "Connexion / Inscription",
      loading: "Chargement...",
      online: "en ligne",
      play: "Jouer",
    },
    language: {
      label: "Langue",
      options: {
        english: "English",
        french: "French",
        arabic: "Arabic",
      },
    },
    legal: {
      close: "Fermer la notice juridique",
      lastUpdated: "Dernière mise à jour : 27 juin 2026",
      privacyPolicy: "Politique de confidentialité",
      privacySections: [
        {
          title: "1. À propos de cette politique",
          body: "Cette politique explique comment Pixel Fight, un jeu multijoueur éducatif créé dans le cadre du cursus 42, traite les données personnelles lorsque vous utilisez le tableau de bord, les fonctions de compte, le chat global et les parties en ligne.",
        },
        {
          title: "2. Données collectées",
          body: "Si vous créez un compte, nous traitons votre adresse e-mail, l’identifiant du fournisseur d’authentification, l’identifiant du joueur, le nom d’utilisateur et l’avatar facultatif. Nous conservons aussi la progression et les parties : niveau, XP, score, éliminations, morts, temps de jeu et dates. Les messages du chat global et la présence en ligne sont traités en temps réel. Un profil invité généré localement est stocké dans le navigateur. Nos fournisseurs d’hébergement et de réseau peuvent traiter des données techniques standard, notamment l’adresse IP, le navigateur, les horodatages et les journaux d’erreurs.",
        },
        {
          title: "3. Utilisation des données",
          body: "Nous utilisons ces données pour authentifier les joueurs, exploiter les parties multijoueurs et le chat, afficher les profils et classements, sauvegarder la progression et l’historique, prévenir les abus, assurer la sécurité, diagnostiquer les pannes et améliorer le service. Nous ne vendons pas les données personnelles et ne les utilisons pas pour de la publicité ciblée.",
        },
        {
          title: "4. Stockage et prestataires",
          body: "Les données de compte, de profil et de partie sont stockées via Supabase. Google ou GitHub traitent des informations si vous choisissez leur connexion OAuth. Le serveur multijoueur traite temporairement les événements de jeu, de présence et de chat en direct. Ces prestataires traitent les données selon leurs propres conditions et politiques.",
        },
        {
          title: "5. Stockage du navigateur",
          body: "Pixel Fight utilise le stockage local du navigateur pour la langue choisie, le profil invité et une mise en cache limitée du profil. Supabase peut utiliser des cookies ou un stockage similaire pour maintenir une session authentifiée. Vous pouvez effacer ces données dans votre navigateur, mais cela peut vous déconnecter ou réinitialiser la progression invitée.",
        },
        {
          title: "6. Durée de conservation",
          body: "Les données du compte et les données de jeu sauvegardées sont conservées tant que le compte reste actif et aussi longtemps que nécessaire au fonctionnement ou à la sécurité du service. Le chat en direct et les événements transitoires ne sont pas destinés à être des archives permanentes. Les journaux techniques peuvent être conservés pendant une période limitée. Après suppression, des données peuvent rester brièvement dans les sauvegardes.",
        },
        {
          title: "7. Vos choix et droits",
          body: "Vous pouvez modifier votre nom d’utilisateur et votre avatar ou supprimer votre compte depuis la fenêtre Profil. La suppression retire le compte et les données Pixel Fight associées des systèmes actifs, sous réserve des sauvegardes temporaires et des données nécessaires à la sécurité ou aux obligations légales. Selon votre pays, vous pouvez aussi demander l’accès, la rectification, l’effacement, la limitation ou l’export de vos données.",
        },
        {
          title: "8. Sécurité et mineurs",
          body: "Nous appliquons des mesures techniques et organisationnelles raisonnables, mais aucun service en ligne ne peut garantir une sécurité absolue. Ne publiez pas d’informations personnelles sensibles dans votre nom ou le chat. Pixel Fight ne s’adresse pas aux enfants de moins de 13 ans, ni aux personnes n’ayant pas atteint l’âge minimum de consentement numérique dans leur pays, et nous ne collectons pas sciemment leurs données.",
        },
        {
          title: "9. Modifications et contact",
          body: "Nous pouvons modifier cette politique si le projet ou ses pratiques évoluent. La date ci-dessus identifie la version actuelle. Les questions et demandes peuvent être adressées aux responsables de Pixel Fight via le dépôt du projet FT_Transcendence.",
        },
      ],
      termsOfService: "Conditions d’utilisation",
      termsSections: [
        {
          title: "1. Acceptation",
          body: "En accédant à Pixel Fight ou en l’utilisant, vous acceptez ces Conditions d’utilisation et la Politique de confidentialité. Si vous refusez, n’utilisez pas le service. Pixel Fight est un projet éducatif du cursus 42 et non un service de jeu commercial.",
        },
        {
          title: "2. Comptes",
          body: "Vous pouvez jouer en invité ou vous connecter par e-mail ou avec un fournisseur OAuth disponible. Vous êtes responsable des activités de votre compte et de la sécurité de vos accès. Choisissez un nom et un avatar appropriés et n’usurpez pas l’identité d’une autre personne.",
        },
        {
          title: "3. Jeu équitable et conduite",
          body: "Il est interdit de tricher, exploiter des failles, automatiser le jeu, perturber les serveurs, contourner la sécurité, harceler autrui ou publier du contenu illégal, haineux, menaçant, sexuellement explicite, trompeur ou portant atteinte à la vie privée. N’envoyez pas de fichiers malveillants, de spam ou de publicité. Nous pouvons limiter l’accès ou supprimer les contenus et comptes en infraction.",
        },
        {
          title: "4. Votre contenu",
          body: "Vous restez responsable des noms, avatars et messages que vous envoyez. Vous accordez à Pixel Fight l’autorisation limitée nécessaire pour héberger, traiter et afficher ce contenu afin de fournir le service. Ne soumettez que du contenu que vous avez le droit d’utiliser.",
        },
        {
          title: "5. Licence du projet",
          body: "Le jeu, le tableau de bord, les illustrations, le code et les autres éléments sont protégés par les droits applicables et les licences indiquées dans le dépôt. Ces conditions ne transfèrent aucun droit de propriété et n’accordent que l’usage du service et les droits expressément prévus par ces licences.",
        },
        {
          title: "6. Disponibilité et modifications",
          body: "Le service est fourni à des fins d’apprentissage et de démonstration. Les fonctions, l’équilibrage, les comptes, la progression et la disponibilité peuvent changer, être réinitialisés ou prendre fin. La maintenance, les pannes ou les prestataires tiers peuvent interrompre l’accès. Nous ne garantissons ni un fonctionnement continu ni la conservation permanente des données de jeu.",
        },
        {
          title: "7. Garantie et responsabilité",
          body: "Dans les limites autorisées par la loi, Pixel Fight est fourni « en l’état » et « selon disponibilité », sans garantie de qualité marchande, d’adaptation à un usage particulier ou d’absence de contrefaçon. Les responsables ne répondent pas des dommages indirects, accessoires, spéciaux, consécutifs ou des pertes de données liés au service. Les droits qui ne peuvent être légalement exclus restent applicables.",
        },
        {
          title: "8. Résiliation",
          body: "Vous pouvez cesser d’utiliser Pixel Fight à tout moment et supprimer un compte authentifié depuis la fenêtre Profil. Nous pouvons suspendre ou résilier un accès lorsque cela est raisonnablement nécessaire pour la sécurité, l’intégrité du service, le respect de la loi ou une violation de ces conditions.",
        },
        {
          title: "9. Mises à jour et contact",
          body: "Nous pouvons réviser ces conditions lorsque le projet évolue. La poursuite de l’utilisation après une mise à jour vaut acceptation. La date ci-dessus identifie la version actuelle. Les questions peuvent être adressées aux responsables de Pixel Fight via le dépôt du projet FT_Transcendence.",
        },
      ],
    },
    profile: {
      apply: "Appliquer",
      applying: "Application...",
      chooseUsername: "Choisissez votre nom",
      close: "Fermer le profil",
      confirm: "Confirmer",
      dateTime: "Date / Heure",
      deleteAccount: "Supprimer le compte",
      deleteAccountConfirm:
        "Supprimer votre compte et toutes vos donnees Pixel Fight ?",
      deletingAccount: "Suppression...",
      death: "Mort",
      exp: "Exp",
      imageRequired: "Choisissez une image PNG, JPG, GIF ou WEBP",
      kills: "Kills",
      level: "Niveau",
      logout: "Deconnexion",
      matchLog: "Historique",
      noMatchLogs: "Aucun historique",
      photoInput: "Choisir une photo",
      playTime: "Temps",
      profile: "Profil",
      saveFailed: "Impossible de sauvegarder",
      saveSuccess: "Profil sauvegarde",
      score: "Score",
      signInToSaveMatchLogs: "Connectez-vous pour sauvegarder les historiques",
      usernameTaken: "Nom deja utilise",
      usernameRequired: "Entrez un nom",
      usernameInput: "Nom du joueur",
    },
  },
  arabic: {
    auth: {
      authFailed: "تعذر تسجيل الدخول بالبريد",
      close: "اغلاق نافذة الدخول",
      code: "الرمز",
      codeRequired: "ادخل رمز التحقق",
      codeSent: "تم ارسال رمز التحقق",
      connectVia: "او اتصل عبر",
      email: "البريد",
      emailRequired: "ادخل بريدك",
      sendCode: "ارسال الرمز",
      sendingCode: "جاري الارسال...",
      verifyCode: "تحقق من الرمز",
      verifyingCode: "جاري التحقق...",
    },
    chat: {
      close: "اغلاق الدردشة العامة",
      cooldown: "انتظر {seconds}ث",
      inputLabel: "رسالة الدردشة العامة",
      open: "الدردشة",
      placeholder: "اكتب رسالة...",
      signInToSend: "سجل للدردشة",
      title: "الدردشة العامة",
      unavailable: "الدردشة غير متاحة",
    },
    fullscreen: {
      enter: "ملء",
      exit: "الخروج",
    },
    home: {
      battleArena: "ساحة القتال",
      loginSignup: "دخول / تسجيل",
      loading: "جاري التحميل...",
      online: "متصل",
      play: "العب",
    },
    language: {
      label: "اللغة",
      options: {
        english: "English",
        french: "French",
        arabic: "العربية",
      },
    },
    legal: {
      close: "إغلاق الإشعار القانوني",
      lastUpdated: "آخر تحديث: 27 يونيو 2026",
      privacyPolicy: "سياسة الخصوصية",
      privacySections: [
        {
          title: "1. حول هذه السياسة",
          body: "توضح هذه السياسة كيفية تعامل Pixel Fight، وهي لعبة جماعية تعليمية أُنشئت ضمن منهج 42، مع البيانات الشخصية عند استخدام لوحة التحكم وميزات الحساب والدردشة العامة والمباريات عبر الإنترنت.",
        },
        {
          title: "2. البيانات التي نجمعها",
          body: "إذا أنشأت حساباً، فإننا نعالج بريدك الإلكتروني ومعرّف مزود المصادقة ومعرّف اللاعب واسم المستخدم والصورة الاختيارية. ونحفظ أيضاً بيانات التقدم والمباريات مثل المستوى والخبرة والنقاط وعدد مرات القتل والموت ومدة اللعب وتواريخ المباريات. تُعالج رسائل الدردشة العامة وحالة الاتصال فورياً. يحصل الضيف على ملف محلي محفوظ في المتصفح. وقد يعالج مزودو الاستضافة والشبكة بيانات تقنية معتادة مثل عنوان IP ونوع المتصفح والطوابع الزمنية وسجلات الأخطاء.",
        },
        {
          title: "3. كيفية استخدام البيانات",
          body: "نستخدم البيانات لمصادقة اللاعبين وتشغيل المباريات والدردشة وعرض الملفات ولوحات الصدارة وحفظ التقدم وسجل المباريات ومنع إساءة الاستخدام وحماية الخدمة وتشخيص الأعطال وتحسينها. لا نبيع البيانات الشخصية ولا نستخدمها للإعلانات الموجهة.",
        },
        {
          title: "4. التخزين ومزودو الخدمة",
          body: "تُخزن بيانات الحساب والملف والمباريات عبر Supabase. يعالج Google أو GitHub معلومات عند اختيار تسجيل الدخول عبر OAuth. ويعالج خادم اللعب الجماعي مؤقتاً أحداث اللعب والحضور والدردشة المباشرة. يتعامل هؤلاء المزودون مع البيانات وفق شروطهم وسياساتهم الخاصة.",
        },
        {
          title: "5. تخزين المتصفح",
          body: "تستخدم Pixel Fight التخزين المحلي في المتصفح لحفظ اللغة والملف الضيف ونسخة مؤقتة محدودة من الملف. وقد يستخدم Supabase ملفات تعريف الارتباط أو تخزيناً مشابهاً للحفاظ على جلسة الدخول. يمكنك مسح هذه البيانات من المتصفح، لكن ذلك قد يسجل خروجك أو يعيد ضبط تقدم الضيف.",
        },
        {
          title: "6. مدة الاحتفاظ",
          body: "نحتفظ ببيانات الحساب واللعب المحفوظة ما دام الحساب نشطاً وبالقدر اللازم لتشغيل الخدمة أو حمايتها. لا يُقصد بالدردشة المباشرة وأحداث اللعب المؤقتة أن تكون سجلات دائمة. قد تُحفظ السجلات التقنية لفترة محدودة لأغراض الإصلاح والأمان. وقد تبقى البيانات لفترة قصيرة في النسخ الاحتياطية بعد الحذف.",
        },
        {
          title: "7. خياراتك وحقوقك",
          body: "يمكنك تعديل اسم المستخدم والصورة أو حذف الحساب من نافذة الملف الشخصي. يزيل الحذف الحساب وبيانات Pixel Fight المرتبطة من الأنظمة النشطة، مع مراعاة النسخ الاحتياطية قصيرة الأجل والسجلات اللازمة للأمان أو الالتزام القانوني. وحسب بلدك، قد يحق لك طلب الوصول أو التصحيح أو المحو أو التقييد أو تصدير بياناتك.",
        },
        {
          title: "8. الأمان والأطفال",
          body: "نستخدم إجراءات تقنية وتنظيمية معقولة، لكن لا يمكن لأي خدمة عبر الإنترنت ضمان الأمان المطلق. لا تشارك معلومات شخصية حساسة في اسمك أو الدردشة. لا تستهدف Pixel Fight الأطفال دون 13 عاماً أو دون سن الموافقة الرقمية في بلدهم، ولا نجمع بياناتهم عن علم.",
        },
        {
          title: "9. التغييرات والتواصل",
          body: "قد نحدّث هذه السياسة عند تغير المشروع أو ممارسات البيانات. يحدد التاريخ أعلاه النسخة الحالية. يمكن إرسال أسئلة وطلبات الخصوصية إلى مشرفي Pixel Fight عبر مستودع مشروع FT_Transcendence.",
        },
      ],
      termsOfService: "شروط الخدمة",
      termsSections: [
        {
          title: "1. القبول",
          body: "باستخدام Pixel Fight فإنك توافق على شروط الخدمة وسياسة الخصوصية. إذا لم توافق فلا تستخدم الخدمة. Pixel Fight مشروع تعليمي أُنشئ ضمن منهج 42 وليس خدمة ألعاب تجارية.",
        },
        {
          title: "2. الحسابات",
          body: "يمكنك اللعب كضيف أو تسجيل الدخول بالبريد أو عبر مزود OAuth متاح. أنت مسؤول عن النشاط في حسابك وعن حماية الوصول إلى بريدك وحسابات المزود. استخدم اسماً وصورة مناسبين ولا تنتحل شخصية غيرك.",
        },
        {
          title: "3. اللعب العادل والسلوك",
          body: "يُحظر الغش واستغلال الأخطاء وأتمتة اللعب وتعطيل الخوادم وتجاوز الحماية ومضايقة الآخرين ونشر محتوى غير قانوني أو يحض على الكراهية أو التهديد أو محتوى جنسي صريح أو مضلل أو منتهك للخصوصية. لا ترفع ملفات ضارة ولا تستخدم الدردشة للإزعاج أو الإعلان. يمكننا تقييد الوصول أو إزالة المحتوى أو الحسابات المخالفة.",
        },
        {
          title: "4. محتواك",
          body: "تظل مسؤولاً عن الأسماء والصور ورسائل الدردشة التي ترسلها. تمنح Pixel Fight إذناً محدوداً لاستضافة هذا المحتوى ومعالجته وعرضه بالقدر اللازم لتشغيل الخدمة. لا ترسل إلا محتوى يحق لك استخدامه.",
        },
        {
          title: "5. ترخيص المشروع",
          body: "اللعبة ولوحة التحكم والرسومات والبرمجيات ومواد المشروع الأخرى محمية بحقوق الملكية والتراخيص الموضحة في مستودع المشروع. لا تنقل هذه الشروط الملكية ولا تمنح حقوقاً تتجاوز استخدام الخدمة والحقوق المنصوص عليها صراحة في تلك التراخيص.",
        },
        {
          title: "6. التوفر والتغييرات",
          body: "تُقدم الخدمة للتعلم والعرض. قد تتغير الميزات وتوازن اللعبة والحسابات والتقدم والتوفر، أو يعاد ضبطها أو تتوقف. قد تقطع الصيانة أو الأعطال أو الخدمات الخارجية الوصول. لا نضمن عملاً متواصلاً أو تخزيناً دائماً لبيانات اللعب.",
        },
        {
          title: "7. إخلاء المسؤولية",
          body: "بالقدر الذي يسمح به القانون، تُقدم Pixel Fight «كما هي» و«حسب التوفر» دون ضمانات تتعلق بالجودة التجارية أو الملاءمة لغرض معين أو عدم الانتهاك. لا يتحمل المشرفون مسؤولية الأضرار غير المباشرة أو العرضية أو الخاصة أو التبعية أو فقدان البيانات الناتج عن استخدام الخدمة. تبقى الحقوق التي لا يجوز استبعادها قانوناً سارية.",
        },
        {
          title: "8. الإنهاء",
          body: "يمكنك التوقف عن استخدام Pixel Fight في أي وقت وحذف الحساب المسجل من نافذة الملف الشخصي. يمكننا تعليق الوصول أو إنهاءه عندما يكون ذلك ضرورياً بشكل معقول للأمان أو سلامة الخدمة أو الامتثال للقانون أو بسبب مخالفة هذه الشروط.",
        },
        {
          title: "9. التحديثات والتواصل",
          body: "قد نراجع هذه الشروط مع تطور المشروع. استمرار الاستخدام بعد التحديث يعني قبول الشروط المعدلة. يحدد التاريخ أعلاه النسخة الحالية. يمكن إرسال الأسئلة إلى مشرفي Pixel Fight عبر مستودع مشروع FT_Transcendence.",
        },
      ],
    },
    profile: {
      apply: "تطبيق",
      applying: "جاري التطبيق...",
      chooseUsername: "اختر اسمك",
      close: "اغلاق الملف الشخصي",
      confirm: "تاكيد",
      dateTime: "التاريخ / الوقت",
      deleteAccount: "حذف الحساب",
      deleteAccountConfirm: "حذف حسابك وكل بيانات Pixel Fight المحفوظة؟",
      deletingAccount: "جاري الحذف...",
      death: "الموت",
      exp: "الخبرة",
      imageRequired: "اختر صورة PNG او JPG او GIF او WEBP",
      kills: "قتل",
      level: "المستوى",
      logout: "خروج",
      matchLog: "سجل المباريات",
      noMatchLogs: "لا يوجد سجل بعد",
      photoInput: "اختر صورة الملف",
      playTime: "المدة",
      profile: "الملف",
      saveFailed: "تعذر حفظ الملف",
      saveSuccess: "تم حفظ الملف",
      score: "النقاط",
      signInToSaveMatchLogs: "سجل الدخول لحفظ سجل المباريات",
      usernameTaken: "الاسم مستخدم",
      usernameRequired: "ادخل اسما",
      usernameInput: "اسم اللاعب",
    },
  },
};
