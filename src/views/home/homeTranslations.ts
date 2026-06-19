export type HomeLanguage = "english" | "french" | "arabic";

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
