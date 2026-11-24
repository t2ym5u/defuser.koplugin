# Changelog

All notable changes to this project will be documented in this file.

## [1.0.3] - 2026-11-24

### Changed
- Picks up game-common 1.18.0: a status line cut off with "…" opens in full
  when tapped, so a long hint can be read.

## [1.0.2] - 2026-11-18

### Changed
- Picks up game-common 1.17.0 (a board redraw fix used by chess, binairo and
  tatami; no change in this game).

## [1.0.1] - 2026-11-18

### Fixed
- The dial's − and + buttons show the new position at once.

## [1.0.0] - 2026-11-10

### Added
- First release: a cooperative game for two players with a reader each.
  Both readers build the same alarm machine and its manual from the game
  code; the operator's reader shows the machine (serial number, modules)
  and checks every action, the expert's reader shows the manual, whose rules
  are drawn anew for every game. Three mistakes and the alarm rings.
- Modules: wires (cut the right one), symbols (press four in the right
  column's order) and dial (set the position the table gives). Easy 3
  modules, Medium 4, Hard 5; time taken shown at the end; auto-save.
