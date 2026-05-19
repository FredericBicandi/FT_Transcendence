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
  };
  home: {
    loginSignup: string;
    online: string;
    play: string;
  };
  language: {
    label: string;
    options: Record<HomeLanguage, string>;
  };
  profile: {
    close: string;
    dateTime: string;
    death: string;
    exp: string;
    kills: string;
    level: string;
    matchLog: string;
    photoInput: string;
    profile: string;
    score: string;
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
    },
    home: {
      loginSignup: "Login / Sign Up",
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
      close: "Close profile popup",
      dateTime: "Date / Time",
      death: "Death",
      exp: "Exp",
      kills: "Kills",
      level: "Level",
      matchLog: "Match Log",
      photoInput: "Choose profile photo",
      profile: "Profile",
      score: "Score",
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
    },
    home: {
      loginSignup: "Connexion / Inscription",
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
      close: "Fermer le profil",
      dateTime: "Date / Heure",
      death: "Mort",
      exp: "Exp",
      kills: "Kills",
      level: "Niveau",
      matchLog: "Historique",
      photoInput: "Choisir une photo",
      profile: "Profil",
      score: "Score",
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
    },
    home: {
      loginSignup: "دخول / تسجيل",
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
      close: "اغلاق الملف الشخصي",
      dateTime: "التاريخ / الوقت",
      death: "الموت",
      exp: "الخبرة",
      kills: "قتل",
      level: "المستوى",
      matchLog: "سجل المباريات",
      photoInput: "اختر صورة الملف",
      profile: "الملف",
      score: "النقاط",
      usernameInput: "اسم اللاعب",
    },
  },
};
