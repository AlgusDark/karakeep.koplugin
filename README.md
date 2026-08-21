# Karakeep KOReader Plugin

A KOReader plugin to access your Karakeep bookmarks directly on your e-reader.

## Features

This plugin integrates with [Karakeep](https://karakeep.app/), a self-hostable “Bookmark Everything” app that lets you save links, notes and images with ai-generated tags them with AI—and uses Karakeep’s REST API (with HTTP Bearer JWT authentication) for secure data access.

### Bookmarks

- [x] Create Bookmarks
  - [x] Save links
  - [x] Export Highlights 
- [x] Browse your bookmarks
  - [x] Browse all bookmarks
  - [x] Browse by list
- [x] Search bookmarks
- [x] Download bookmarks for offline access (EPUB)

## Prerequisites

- KOReader **2025.04** or later
- A running Karakeep instance (v0.25.0+)
- An API key generated in Karakeep under **User Settings > API Keys**

## Installation

1. Download latest release from the [Releases](https://github.com/AlgusDark/karakeep.koplugin/releases) page.
2. Extract the `karakeep.koplugin` folder into your KOReader `plugins/` directory.
3. Restart KOReader.
4. Enable **Karakeep** under **Settings > Plugins**.

## Configuration

1. In KOReader, go to **Tools > Karakeep**.
2. Set the **Server address** (e.g. `https://karakeep.example.com`).
3. Enter your **API token**.
4. Optionally set a **proxy** as `host:port` if your Karakeep instance is only
   reachable through a local HTTP proxy. Leave empty to connect directly.
5. Save and exit.

### Reaching a Karakeep instance behind a proxy

If Karakeep is only routable through a local HTTP proxy, set the proxy field to
that address. The common case is Tailscale running in userspace-networking mode
(the default on e-readers, since kernel TUN triggers wgengine watchdog timeouts),
where `tailscaled` exposes an HTTP CONNECT proxy on `127.0.0.1:1056` rather than
creating a TUN interface. Without this, requests to a tailnet-only address fail
at the socket layer, because LuaSocket has no CONNECT tunnelling and LuaSec
refuses to combine TLS with a proxy.

## Usage

### Bookmarking links

A new **"Save to Karakeep"** option will appear in the links dialog action when clicking a link.

- If there is a network or server issue, the plugin will queue the item locally and sync it as soon as connectivity is restored, or when you manually trigger a sync.
