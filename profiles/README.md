# Community profiles

This folder is a shareable library of NagaController profile collections. Download a JSON file, then use **Manage Profiles → Import…** in NagaController. Imports merge into your existing library; they do not delete your current profiles.

## Included collection

- [`community/desk-code-game.json`](community/desk-code-game.json) provides three linked profiles:
  - **Desk** for copy/paste, editing, browser history, screenshots, and media controls.
  - **Code** for common development actions and editor navigation.
  - **Game** with a simple 1–8 ability layout and an F1–F8 function layer.

Buttons 10–12 always switch to **Desk**, **Code**, and **Game**, so the collection stays navigable from every profile.

## DPI and wheel controls

The included collection leaves **DPI Up** and **DPI Down** native. The mouse keeps its on-board sensitivity stages, while NagaController displays the reported DPI value and stage meter. Wheel tilt and wheel click may need one-time pairing through **Learn Hardware Trigger…** after import.

## Share a profile

Add a tested JSON collection under `profiles/community/`, include a short description in this README, and open a pull request. Please use a descriptive filename, document the mouse model and connection mode you tested, avoid private paths or account-specific data, and do not include shell-command actions.
