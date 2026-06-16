export type HomeLanguage = "english" | "french" | "arabic";

export type HomeTranslations = {
  auth: {
    close: string;
    connectVia: string;
    email: string;
    loginRegister: string;
  };
  chat: {
    inputLabel: string;
    placeholder: string;
    signInToSend: string;
    unavailable: string;
  };
  fullscreen: {
    enter: string;
    exit: string;
  };
  home: {
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
      close: "Close login popup",
      connectVia: "----Or Connect Via----",
      email: "email",
      loginRegister: "Login / Register",
    },
    chat: {
      inputLabel: "Global chat message",
      placeholder: "Type message...",
      signInToSend: "Sign in to chat",
      unavailable: "Chat unavailable",
    },
    fullscreen: {
      enter: "Enter fullscreen",
      exit: "Exit fullscreen",
    },
    home: {
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
      close: "Fermer la fenetre de connexion",
      connectVia: "----Ou Connectez-Vous Via----",
      email: "email",
      loginRegister: "Connexion / Inscription",
    },
    chat: {
      inputLabel: "Message du chat global",
      placeholder: "Ecrire un message...",
      signInToSend: "Connectez-vous pour chatter",
      unavailable: "Chat indisponible",
    },
    fullscreen: {
      enter: "Plein ecran",
      exit: "Quitter le plein ecran",
    },
    home: {
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
      close: "اغلاق نافذة الدخول",
      connectVia: "----او اتصل عبر----",
      email: "البريد",
      loginRegister: "دخول / تسجيل",
    },
    chat: {
      inputLabel: "رسالة الدردشة العامة",
      placeholder: "اكتب رسالة...",
      signInToSend: "سجل للدردشة",
      unavailable: "الدردشة غير متاحة",
    },
    fullscreen: {
      enter: "ملء الشاشة",
      exit: "الخروج من ملء الشاشة",
    },
    home: {
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
        arabic: "Arabic",
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
