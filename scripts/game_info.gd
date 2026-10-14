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
const PRIVACY_URL := ""
