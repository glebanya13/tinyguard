class_name MercenaryConfig
extends Resource
## Numbers of the Mercenary Camp (resources/mercenary.tres): the price grows with every hire of
## the battle, only a few knights may be alive at once, and they take damage from the enemies
## they fight (so they die and do not sweep the lanes on their own).

## Gold of the first hire of a battle.
@export var hire_gold: int = 40
## Every hire of this battle (dead ones count too) makes the next one this much dearer.
@export var hire_gold_step: int = 20
## At most this many mercenaries alive at once.
@export var max_alive: int = 3

@export_group("Fighter")
@export var max_health: float = 80.0
@export var attack_damage: float = 16.0

@export_group("Taking damage")
## Enemies this close (metres, flat) bite the mercenary.
@export var contact_radius: float = 0.9
## Damage a second from one biting enemy per point of its castle damage (`base_damage`):
## a plain chupacabra 6/s, a tank 12/s, a king 30/s.
@export var contact_dps: float = 6.0
## The bite grows with the wave like the crowd does: +this share per wave after the first.
@export var contact_growth_per_wave: float = 0.04


## Gold of the next hire after `hired` hires this battle.
func hire_cost(hired: int) -> int:
	return hire_gold + hire_gold_step * maxi(hired, 0)


## Damage a second one enemy with `base_damage` of `wave` deals to a mercenary.
func bite_dps(base_damage: int, wave: int) -> float:
	return contact_dps * maxi(base_damage, 1) * (1.0 + contact_growth_per_wave * maxi(wave - 1, 0))
