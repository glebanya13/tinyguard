class_name GameInfo
extends RefCounted
## Product constants used by the onboarding and account screens. The title shown
## on new screens lives only here, so a rename is a one-line change.

## Game title on the boot, nickname and account screens. The owner currently
## calls the product "Bimbleguard"; the project stays "Bimbleguard" until the
## rename is decided (project.godot, splash and the map title are unchanged).
const TITLE := "Bimbleguard"
## Public privacy policy page (docs/PRIVACY.md published somewhere, e.g. on
## Firebase Hosting). Empty: the account panel shows a short summary instead.
const PRIVACY_URL := "https://tinyguard.app/privacy"
## Public web page where a player can request deletion of the account and its
## data without the app (Google Play requires it for apps with accounts; it goes
## into the Data safety form).
const DELETION_URL := "https://tinyguard.app/delete-account"
## Support e-mail shown in the privacy policy and the store listing.
const SUPPORT_EMAIL := "support@tinyguard.app"
## Feedback form URL for external playtesters.
const FEEDBACK_URL := "https://tinyguard.app/feedback"


## The profile line about deleting data from the web, or "" while the URL is unset.
static func web_deletion_line() -> String:
	if DELETION_URL == "":
		return ""
	return TranslationServer.translate("INFO_DELETION_WEB") % DELETION_URL
