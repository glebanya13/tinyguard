class_name EnemyData
extends Resource
## Enemy type: model and base stats (health is multiplied by the wave).

@export var display_name: String = ""
@export var model: PackedScene
@export var health: float = 20.0
## Metres per second along the path.
@export var speed: float = 1.2
@export var reward: int = 3
## Lives the castle loses when this enemy reaches it.
@export var base_damage: int = 1
## Colour of the puff when it dies (visual effects only).
@export var fx_color: Color = Color(0.9, 0.4, 0.35)
@export var health_bar_height: float = 0.8
@export var health_bar_width: float = 0.6
@export var is_boss: bool = false
## Flies above the path: cannon shells cannot hit it.
@export var flying: bool = false
## Height of the model above the path when flying (metres).
@export var fly_height: float = 0.0
## Damage multiplier for arrows (a shield bearer takes less).
@export var arrow_damage_mult: float = 1.0
## On death, splits into `split_count` enemies of `split_into` (null = no split).
@export var split_into: EnemyData
@export var split_count: int = 0
## Heals other enemies within heal_radius by heal_fraction of their max health
## every heal_interval seconds (0 = not a healer).
@export var heal_fraction: float = 0.0
@export var heal_radius: float = 1.8
@export var heal_interval: float = 1.0
## Flat damage removed from every hit (at least 1 damage always goes through).
@export var armor: float = 0.0
