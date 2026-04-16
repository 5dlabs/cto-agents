# Playwright MCP Tools

## Overview
Browser automation for end-to-end testing, web scraping, and UI interaction.

## Capabilities
- Browser page navigation and interaction
- Element clicking, typing, and form filling
- Screenshot and PDF generation
- Network request interception
- Multi-browser support (Chromium, Firefox, WebKit)

## Tool Prefix
`playwright_*` — 22 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `playwright_navigate` | Navigate to a URL |
| `playwright_click` | Click an element by selector |
| `playwright_fill` | Fill a form input field |
| `playwright_screenshot` | Take a screenshot of the page |
| `playwright_get_text` | Get text content of an element |
| `playwright_evaluate` | Execute JavaScript in the browser |
| `playwright_wait_for_selector` | Wait for an element to appear |
| `playwright_select_option` | Select a dropdown option |

## Configuration
Transport: In-cluster MCP server. Browser: Headless Chromium.

## When to Use
- End-to-end testing of web applications
- Scraping dynamic (JavaScript-rendered) pages
- Automating web-based workflows
- Taking screenshots for visual regression testing

## Tags
browser-automation, e2e-testing, web-scraping, ui-testing, screenshots
