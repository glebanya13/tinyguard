import type { Content } from "./types";

const faqProfile =
  "Open Profile, then Delete account. Details and the e-mail request are on the [account deletion](/delete-account/) page.";

export const en: Content = {
  locale: "en",
  htmlLang: "en",
  ogLocale: "en_US",
  ui: {
    skip: "Skip to content",
    menu: "Open menu",
    closeMenu: "Close menu",
    mainNav: "Main navigation",
    mobileNav: "Mobile navigation",
    homeAria: "Bimbleguard: home",
    navHome: "Home",
    navAbout: "About the Game",
    navPrivacy: "Privacy Policy",
    navContact: "Contact",
    navTerms: "Terms of Use",
    navSupport: "Support",
    comingSoon: "Coming Soon",
    comingSoonPlay: "Coming Soon to Google Play",
    getOnPlay: "Get it on Google Play",
    madeFor: "Made for Android",
    footerTagline: "Bimbleguard is a fantasy tower defense game for Android.",
    copyright: "Bimbleguard. All rights reserved.",
    langOther: "RU",
    langOtherName: "Русский",
    langSwitchLabel: "Site language",
    close: "Close",
    openShot: "Open screenshot",
    prev: "Previous screenshot",
    next: "Next screenshot",
    goTo: "Go to screenshot",
    carousel: "Game screenshots",
    operator: "Operator",
    contact: "Contact",
    policyVersion: "Text version",
    contactTitle: "Get in touch",
    contactLead: "A question about the game, a bug or a data deletion request: write to us.",
    contactSoon: "Contact details will be published here soon.",
    notFoundTitle: "Page not found",
    notFoundLead: "There is no such page. Go back to the home page or open support.",
    notFoundBack: "Back to home",
  },
  meta: {
    home: {
      title: "Bimbleguard: Tower Defense for Android",
      description:
        "Bimbleguard is a light 3D tower defense for phones. 6 levels, a hero you control, 4 towers, a Daily Challenge and co-op. No ads, works offline.",
    },
    privacy: {
      title: "Privacy Policy: Bimbleguard",
      description:
        "What data the game Bimbleguard processes, why, where it is stored and how to delete it. No ads, analytics or tracking.",
    },
    deleteAccount: {
      title: "Delete your account and data: Bimbleguard",
      description:
        "How to delete a Bimbleguard account and related data: in the game via Profile, Delete account, or by an e-mail request.",
    },
    support: {
      title: "Support: Bimbleguard",
      description:
        "Bimbleguard support contacts and answers to common questions: progress, cloud save, account, online features.",
    },
    terms: {
      title: "Terms of Use: Bimbleguard",
      description: "Simple terms of use for the game Bimbleguard and this website.",
    },
    about: {
      title: "About the Game: Bimbleguard",
      description:
        "6 levels, a hero you control, 4 towers, a Daily Challenge, co-op and more. No ads, works offline.",
    },
    contact: {
      title: "Contact: Bimbleguard",
      description: "How to contact the Bimbleguard team: questions, bug reports and data requests.",
    },
    notFound: { title: "Page not found: Bimbleguard", description: "Page not found." },
  },
  about: {
    eyebrow: "Game",
    title: "About the Game",
    lead: "What is inside Bimbleguard: levels, towers, the hero and how to play.",
    features: {
      title: "What is inside",
      lead: "Short phone sessions: 10 to 25 minutes per level, designed for landscape play.",
      items: [
        {
          icon: "map",
          title: "6 levels",
          text: "From the green valley to the sand fortress, with winter, autumn and desert maps. Difficulty rises with every level.",
        },
        {
          icon: "route",
          title: "3 to 5 roads",
          text: "Enemies walk to the castle along several paths from different sides of the map and merge at the gate. Choose where to build.",
        },
        {
          icon: "swords",
          title: "A hero you control",
          text: "Run with the joystick, chop trees, hit chupacabras with the sword and trade with villagers. The camera follows the hero.",
        },
        {
          icon: "castle",
          title: "4 towers",
          text: "Archer, Cannon, Frost and Lightning. Three upgrade levels, target priority and synergy: Lightning hits slowed enemies harder.",
        },
        {
          icon: "hourglass",
          title: "Daily Challenge",
          text: "A new level and set of modifiers every day, the same for everyone. Day streaks and bonus stars.",
        },
        {
          icon: "trophy",
          title: "Achievements and records",
          text: "16 achievements and Endless Siege: how many waves can you hold? A player leaderboard.",
        },
        {
          icon: "users",
          title: "Co-op for two",
          text: "Play together with a room code. The online mode is optional and available when enabled in your version of the game.",
        },
        {
          icon: "wifiOff",
          title: "Works offline",
          text: "The whole campaign needs no internet. Online features (leaderboard, cloud save) are optional.",
        },
        {
          icon: "languages",
          title: "English and Russian",
          text: "The language follows the system locale and can be switched in the game settings.",
        },
      ],
    },
    towers: {
      title: "Four towers",
      lead: "Every tower has its own role. A tower can be sold for 70% of what you invested.",
      costLabel: "Cost",
      items: [
        {
          name: "Archer",
          role: "Fast, single target; weak against shields.",
          cost: "15 gold + 10 wood",
        },
        {
          name: "Cannon",
          role: "Slow, area damage; cannot hit flyers.",
          cost: "40 gold + 30 wood",
        },
        { name: "Frost", role: "Slows enemies.", cost: "30 gold + 30 wood" },
        {
          name: "Lightning",
          role: "Chains through 3 to 5 enemies; hits frost-slowed ones 40% harder.",
          cost: "50 gold + 40 wood",
        },
      ],
    },
    gallery: {
      title: "Screenshots",
      lead: "Frames from the game: the kingdom map, levels and towers.",
      shots: [
        {
          file: "shot_01_map",
          caption: "Choose a level",
          alt: "Kingdom map: islands with levels and stars",
        },
        {
          file: "shot_02_level_1_valley",
          caption: "Build towers",
          alt: "Green Valley level: towers by the path and a pack of chupacabras",
        },
        {
          file: "shot_03_level_4_snow",
          caption: "Snowy Pass",
          alt: "Snowy Pass level: towers among snowy fir trees",
        },
        {
          file: "shot_04_level_5_autumn",
          caption: "Autumn Grove",
          alt: "Autumn Grove level with towers and a wave of enemies",
        },
        {
          file: "shot_05_level_6_desert",
          caption: "Sand Fortress",
          alt: "Sand Fortress level in the desert",
        },
        {
          file: "shot_06_upgrade",
          caption: "Upgrade your towers",
          alt: "Tower card with an upgrade and target selection",
        },
        {
          file: "shot_07_tutorial",
          caption: "Learn as you play",
          alt: "Tutorial: a hint on how to build the first tower",
        },
        {
          file: "shot_08_treasury",
          caption: "Spend your stars",
          alt: "Royal Treasury: permanent upgrades bought with stars",
        },
      ],
    },
    how: {
      title: "How to play",
      lead: "The loop is simple: wood, gold, towers, wave.",
      steps: [
        {
          title: "Chop trees",
          text: "Tap a tree and the hero walks over and cuts it. 4 hits give 12 wood, and the tree grows back in a minute.",
        },
        {
          title: "Hit chupacabras",
          text: "Defeated enemies drop gold. Next to a chupacabra or a tree the hero strikes on his own.",
        },
        {
          title: "Build and upgrade towers",
          text: "Pick a marked plot and place a tower. Upgrade towers for gold and wood, sell the ones you do not need.",
        },
        {
          title: "Repel the waves",
          text: "Enemies come from different sides: the banner names the sides and the portals pulse. If the castle runs out of lives you lose; repel every wave to win.",
        },
        {
          title: "Collect stars",
          text: "Up to 3 stars per level. In the Royal Treasury stars become permanent upgrades: gold, wood, walls, sword, towers, axe.",
        },
      ],
      controls:
        "Phone controls: a joystick to move, a strike button, pinch to zoom, pause and x2 speed. The game pauses on a call or when minimized.",
    },
    faq: {
      title: "Frequently asked questions",
      lead: "If your question is not here, see the support page.",
      items: [
        {
          q: "Do I need internet?",
          a: "No. The campaign, the Daily Challenge and Endless Siege work offline. You only need internet for the optional features: leaderboard, cloud save and co-op.",
        },
        {
          q: "Are there ads or purchases?",
          a: "No ads, no in-app purchases and no analytics. The game is free.",
        },
        {
          q: "How do I continue on another phone?",
          a: "Create an account (e-mail and password) on the first screen or in Profile: your progress is saved in the cloud, so you can sign in on another device and reset the password. You can also play without an account (“Play without an account”), but then progress stays tied to this device.",
        },
        {
          q: "What data do you collect?",
          a: "An anonymous ID, the nickname you choose and your game progress, and only when online features are on. See the [privacy policy](/privacy/) for details.",
        },
        { q: "How do I delete my account and data?", a: faqProfile },
        {
          q: "Which devices are supported?",
          a: "The game is made for Android phones in landscape orientation.",
        },
        {
          q: "What is the Daily Challenge?",
          a: "An Endless Siege on a level picked by the UTC date, the same for everyone, with the day's modifiers. It works offline; reaching wave 10 gives a bonus star (no more than 10 in total).",
        },
      ],
    },
  },
  home: {
    artAlt:
      "The Bimbleguard hero in a blue helmet with a sword and shield, a chupacabra king in a golden crown and the castle",
    badge: "A cartoon tower defense adventure",
    title: "Bimbleguard",
    lead: "Build powerful defenses, control your hero, and stop waves of enemies in a colorful fantasy world.",
    introTitle: "Your Castle. Your Strategy.",
    introText:
      "Bimbleguard is a cartoon tower defense game where every path needs a plan. Build your defenses, join the fight with your hero, and prepare for incoming enemy waves.",
  },
  contact: {
    eyebrow: "Contact",
    title: "Contact",
    lead: "Questions about the game, bug reports and data requests: write to us.",
    sections: [],
  },
  privacy: {
    eyebrow: "Document",
    title: "Privacy Policy",
    lead: "The game works offline. We do not use ads, behavioural analytics, tracking or geolocation and do not ask for a phone number or your real name. The one exception is anonymous crash reports (Firebase Crashlytics, Android only): they are on by default and can be turned off in the game settings. E-mail is needed only for an account; you can play without one.",
    sections: [
      {
        id: "short",
        title: "In short",
        blocks: [
          {
            t: "p",
            text: "Online features (leaderboard, cloud save and co-op) are on only in builds with Firebase configured. The main way to sign in is an **account with e-mail and password**, so progress survives a new phone or a reinstall. You can also play **without an account** (“Play without an account”): then no e-mail is collected and progress is tied to this device. For an account we process the e-mail and password through Firebase Authentication and send you a confirmation e-mail; the game is not blocked until the e-mail is confirmed.",
          },
          {
            t: "p",
            text: "Without the online mode (an offline build) **nothing** is sent to a server: your data stays in the save file on your device.",
          },
        ],
      },
      {
        id: "data",
        title: "What data is processed",
        blocks: [
          {
            t: "table",
            head: ["Data", "Why", "Where it is stored"],
            rows: [
              [
                "A random anonymous ID (uid)",
                "To tell players apart and attach progress",
                "Firebase Authentication, Firestore",
              ],
              [
                "The game nickname you choose (3 to 16 characters)",
                "To show it in the leaderboard and keep it unique",
                "Firestore (public profile, nicknames, records)",
              ],
              [
                "Progress: stars, unlocked levels, upgrades, siege records",
                "Sync between sessions and devices",
                "Firestore (user profile)",
              ],
              [
                'Settings (sound) and "onboarding/tutorial done" flags',
                "The same",
                "Firestore (user profile)",
              ],
              [
                'Daily Challenge result: date, wave, nickname (or "Knight"), server time',
                "The daily leaderboard",
                "Firestore; deleted together with the account (records for today and yesterday; the rules do not allow older ones)",
              ],
              [
                "Unlocked achievements (a bit mask) and Daily Challenge bonus stars",
                "Sync between devices",
                "Firestore (user profile)",
              ],
              [
                "Gem balance (an in-game currency, never sold for money), earned rewards, bought cosmetics and chosen skins, day streak",
                "Sync between devices",
                "Firestore (user profile)",
              ],
              ["Profile creation and update time", "Order of merging data", "Firestore"],
              [
                "Start time of an Endless Siege run and time of the last nickname change (without the nickname itself)",
                "To check records against time, a limit of one nickname change per 24 hours",
                "Firestore",
              ],
              [
                "A co-op room (only if you play together and the online mode is on): uid, nickname, room code, chosen level, technical game numbers and your game commands (build, upgrade and so on)",
                "To pass your actions to your partner in real time",
                "Firebase Realtime Database",
              ],
              [
                "**Crash reports** (Firebase Crashlytics; on by default, turn off in Settings, Send crash reports; Android only): crash log and stack trace; de-identified game breadcrumbs (level number, mode, difficulty, wave number, graphics quality step, memory peak); why the previous run ended according to Android (for example, killed by the system for low memory) with its memory use; device model and manufacturer, Android version, memory size and state, free storage, game version; the Crashlytics installation identifier (Firebase Installation ID: random, not linked to your account or e-mail)",
                "To find and fix crashes and freezes, especially on weak phones",
                "Firebase Crashlytics (Google); Google keeps it for 90 days by default",
              ],
              [
                "Session refresh token",
                "To keep you signed in",
                "Only on your device, in an encrypted file",
              ],
              [
                "**E-mail and password** (only if you created an account or linked an e-mail; guests do not need them)",
                "Sign-in on another device, an e-mail confirmation message, a password reset e-mail",
                "Firebase Authentication. Google stores the password as a hash; the game stores neither the password nor the e-mail on the device and writes them neither to cloud data nor to logs",
              ],
            ],
          },
          {
            t: "p",
            text: "Your nickname is visible to other players (leaderboard). **Do not put your real name or contacts in a nickname.** A game nickname should not be personal data; because an anonymous uid and a nickname together can identify a player indirectly, we treat them as personal data and let you delete them.",
          },
        ],
      },
      {
        id: "coop",
        title: "Co-op rooms",
        blocks: [
          {
            t: "p",
            text: "They are needed only to play together and work only when the online mode is enabled in the build. A room contains your uid, nickname, level number and a stream of game commands with tick numbers; your room partner sees the nickname and commands, outsiders read only what is needed to join with a code (the host nickname, the level).",
          },
          {
            t: "p",
            text: "A room lives until the host leaves or until it expires (2 hours); the host deletes it on exit, and an empty room closes after 10 minutes. There is no server-side cleanup (the Spark plan), so a forgotten room may be kept longer than that until the operator deletes it manually; it holds nothing except what is listed. **Profile, Delete account removes both your room and your entry in someone else's room**; this needs internet. Co-op results do not enter the leaderboards and do not change cloud progress.",
          },
        ],
      },
      {
        id: "none",
        title: "What we do not have",
        blocks: [
          {
            t: "p",
            text: "Ads, behavioural analytics (Firebase Analytics and the like), advertising identifiers, geolocation, contacts, camera, microphone, payment data, children's data beyond the above, sharing data with advertising or data broker networks. Data is not sold.",
          },
        ],
      },
      {
        id: "recipients",
        title: "Who receives the data",
        blocks: [
          {
            t: "p",
            text: "Only Google (Firebase Authentication, Cloud Firestore, Firebase Crashlytics for crash reports and, for co-op, Realtime Database) as a processor on our behalf; e-mail confirmation and password reset messages are sent by Firebase. We do not see your password after it is sent to Firebase. Google may process technical request data (for example, the IP address) under its own rules: [Firebase privacy](https://firebase.google.com/support/privacy). There are no other recipients.",
          },
        ],
      },
      {
        id: "rights",
        title: "Your rights and deletion",
        blocks: [
          {
            t: "ul",
            items: [
              "**Delete everything**: Profile, Delete account (see the [account deletion](/delete-account/) page). This removes the nickname and its uniqueness entry, the public profile, the private profile, the cloud save, records on all levels, the run start time and the user in Firebase Authentication (with the linked e-mail), then the data on the device. If you signed in long ago, the game asks you to sign in again and then repeat the deletion. Internet is required (the cloud part cannot be deleted offline); without the online mode only local data is erased.",
              "**Sign out**: Profile, Sign out (for an account with an e-mail): data on the device is erased, cloud data stays under your e-mail. Forgot your password: Sign in, Forgot password. A guest cannot sign out: to keep your progress, create an account (it attaches to the same ID, progress stays).",
              "**Crash reports**: turn off Settings, Send crash reports (takes effect at once, no restart). Reports already sent are not linked to your account or nickname; to have them deleted, write to the contact below with the phone model and the approximate time: they are deleted by hand or expire with Google's retention period.",
              "**Fix your nickname**: Profile, change name (no more than once per 24 hours).",
              "**Get your data**: progress is a file on your device; on request to the contact below the cloud copy can be exported by uid (Profile shows it).",
              "If an account is deleted less than 24 hours after a nickname change, a record remains (only the uid and the change time, no nickname): the rules do not allow deleting it earlier, and the Authentication user is already gone. It has no nickname and is useless without an account; the operator may delete such records manually.",
              "Copies in Google's backup systems are deleted on their internal schedule. We keep no backups of our own.",
            ],
          },
        ],
      },
      {
        id: "retention",
        title: "Retention",
        blocks: [
          {
            t: "p",
            text: "For as long as the account exists. After deletion, see above. Inactive anonymous accounts may be deleted by Google or by us after a period of inactivity.",
          },
        ],
      },
      {
        id: "children",
        title: "Children",
        blocks: [
          {
            t: "p",
            text: "The game is not meant to collect data about children. We collect nothing beyond the data listed above.",
          },
        ],
      },
      {
        id: "security",
        title: "Security",
        blocks: [
          {
            t: "p",
            text: "Data is sent over HTTPS. Access is limited by rules: a player reads and writes only their own documents, others' data is not accessible (except the public nickname and records). The web API key in the app is a project identifier, not a secret. Tokens and profile data are not written to game logs. There is no absolute security.",
          },
        ],
      },
      {
        id: "changes",
        title: "Changes",
        blocks: [
          {
            t: "p",
            text: "The text version date is shown at the top of the page. When the set of data changes we update this document and its version date.",
          },
        ],
      },
      {
        id: "site",
        title: "This website",
        blocks: [
          {
            t: "p",
            text: "The site is static: it has no forms, ads, analytics or cookies, and its fonts are loaded from the site itself, so your browser does not contact third-party servers.",
          },
        ],
      },
    ],
  },
  deleteAccount: {
    eyebrow: "Account and data",
    title: "Delete your account and data",
    lead: "How to delete a Bimbleguard account and the data linked to it. An account is created with an e-mail and password or, if you play without an account, as anonymous; an e-mail can be linked later.",
    sections: [
      {
        id: "in-app",
        title: "Option 1. In the game (recommended)",
        blocks: [
          {
            t: "ol",
            items: [
              "Open the game and go to Profile.",
              "Tap Delete account and confirm.",
              "If you signed in long ago, the game asks you to sign in again (for an account with an e-mail): do so and repeat the deletion.",
            ],
          },
          {
            t: "p",
            text: "Internet is required: the cloud part cannot be deleted offline, and local data is not touched until the deletion succeeds. Without the online mode (an offline build) only local data is erased.",
          },
        ],
      },
      {
        id: "what",
        title: "What is deleted",
        blocks: [
          {
            t: "ul",
            items: [
              "the nickname and its uniqueness entry;",
              "the public profile and the private profile;",
              "the cloud save (progress, settings, achievements);",
              "Endless Siege records on all levels and the run start time;",
              "Daily Challenge results for today and yesterday (the rules do not allow older ones);",
              "the co-op room you created and your entry in someone else's room;",
              "the user in Firebase Authentication with the linked e-mail (if there was one);",
              "data on the device: the game returns to its first launch.",
            ],
          },
        ],
      },
      {
        id: "stays",
        title: "What may remain",
        blocks: [
          {
            t: "ul",
            items: [
              "If the nickname was changed less than 24 hours ago, a record remains holding only the uid and the change time (no nickname): the rules do not allow deleting it earlier. It is useless without an account; the operator deletes such records manually.",
              "Copies in Google's backup systems are deleted on their internal schedule. We keep no backups of our own.",
            ],
          },
        ],
      },
      {
        id: "email",
        title: "Option 2. By e-mail, if the game is unavailable",
        blocks: [
          {
            t: "p",
            text: "If you no longer have the app or the device, write to the support address (shown below) and include your player ID (uid, shown in Profile) and your nickname. If an e-mail was linked to the account, write from that address.",
          },
        ],
      },
    ],
  },
  support: {
    eyebrow: "Help",
    title: "Support",
    lead: "Answers to common questions and contacts. If your question is not listed, write to us.",
    sections: [
      {
        id: "report",
        title: "If something does not work",
        blocks: [
          {
            t: "p",
            text: "In your e-mail include the game version, the phone model and Android version, and what you did before the problem. Never send passwords.",
          },
        ],
      },
    ],
    faqTitle: "Questions and answers",
    faq: [
      {
        q: "My progress is gone. What now?",
        a: "Progress is kept in a file on the device and, if online features are on, in the cloud. Create an account with an e-mail in Profile (or on the first screen) to sign in on another device.",
      },
      {
        q: "How do I link an e-mail and reset the password?",
        a: "Profile, Create account (or Sign in). Forgot your password: Sign in, Forgot password; Firebase sends the e-mail. Firebase also sends the e-mail confirmation message; the game works without confirming.",
      },
      {
        q: "How do I change my nickname?",
        a: "Profile, change name, no more than once per 24 hours. Do not use your real name or contacts.",
      },
      { q: "How do I delete my account and data?", a: faqProfile },
      {
        q: "The leaderboard or co-op does not work.",
        a: "These are online features: they need internet and work only if enabled in your version of the game. The campaign, the Daily Challenge and Endless Siege work offline.",
      },
      {
        q: "The sound bothers me.",
        a: "Turn the sound off in the game settings; the setting is saved.",
      },
    ],
  },
  terms: {
    eyebrow: "Document",
    title: "Terms of Use",
    lead: "Short and simple terms for the game Bimbleguard and this website.",
    sections: [
      {
        id: "game",
        title: "The game",
        blocks: [
          {
            t: "p",
            text: "Bimbleguard is free, with no ads and no in-app purchases. You may use it for personal play on your own device.",
          },
        ],
      },
      {
        id: "nickname",
        title: "Nickname and leaderboard",
        blocks: [
          {
            t: "p",
            text: "Your nickname is visible to other players. Do not use your real name, contacts or offensive words. Records and nicknames that break these rules may be removed manually.",
          },
        ],
      },
      {
        id: "account",
        title: "Account",
        blocks: [
          {
            t: "p",
            text: "Signing in with e-mail and password is the main way; the no-account (anonymous) mode stays available. You can delete your account and data at any time: see [account deletion](/delete-account/).",
          },
        ],
      },
      {
        id: "as-is",
        title: "No warranty",
        blocks: [
          {
            t: "p",
            text: "The game and the site are provided as is. Online features (leaderboard, cloud save, co-op) are optional and may change or be unavailable. We try to keep your progress safe but do not guarantee it.",
          },
        ],
      },
      {
        id: "privacy",
        title: "Data",
        blocks: [
          {
            t: "p",
            text: "What data is processed is described in the [privacy policy](/privacy/).",
          },
        ],
      },
      {
        id: "credits",
        title: "Credits",
        blocks: [
          {
            t: "p",
            text: "Icons in the game are based on works from game-icons.net by Lorc, Delapouite and Carl Olsen, licensed under CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). The icons were recoloured and edited. Icons made by Lorc, Delapouite and Carl Olsen. Available on https://game-icons.net",
          },
          {
            t: "p",
            text: "Fonts: Rubik and Nunito, SIL Open Font License 1.1. All other art, models and sounds are made by the authors of the game.",
          },
        ],
      },
      {
        id: "changes",
        title: "Changes",
        blocks: [
          {
            t: "p",
            text: "The terms may change. The current text is always published on this page.",
          },
        ],
      },
    ],
  },
};
