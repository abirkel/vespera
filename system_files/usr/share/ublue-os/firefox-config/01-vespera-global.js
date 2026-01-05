// Vespera Global Firefox Configuration
// Merged from upstream sources - manually tracked
// 
// Upstream sources:
// - Aurora: https://github.com/get-aurora-dev/common/blob/main/system_files/shared/usr/share/ublue-os/firefox-config/01-aurora-global.js
// - Bazzite: https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/share/ublue-os/firefox-config/01-bazzite-global.js

// From Aurora: Force WebRender GPU acceleration
pref("gfx.webrender.all", true);

// From both Aurora and Bazzite: Force hardware video decoding
pref("media.hardware-video-decoding.force-enabled", true);

// From Bazzite: Disable privacy-concerning features
pref("reader.parse-on-load.enabled", false);
pref("media.webspeech.synth.enabled", false);
pref("browser.tabs.groups.smart.enabled", false);
pref("browser.ml.chat.enabled", false);
pref("extensions.ml.enabled", false);
pref("browser.ml.enable", false);

// Vespera: Enable userChrome.css support for custom styling
pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
