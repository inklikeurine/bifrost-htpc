// Prefs for the bifrost web-app profiles (Twitch, Dropout).
// Copied into each profile by bifrost-webapp on every launch.

// No first-run, welcome or default-browser screens.
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.translations.automaticallyPopup", false);

// The weekly reboot kills Firefox; don't greet the next launch with a restore prompt.
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.tabs.warnOnClose", false);

// Let video start without a click, and don't ask to show notifications.
user_pref("media.autoplay.default", 0);
user_pref("permissions.default.desktop-notification", 2);

// No "press Esc to exit full screen" banner.
user_pref("full-screen-api.warning.timeout", 0);
