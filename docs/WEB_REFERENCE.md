# Web reference and visual translation

Reference: [sonarpratik5/folio](https://github.com/sonarpratik5/folio), inspected locally on 2026-11-14. Its HEAD was `02545f9bff3d4640fdaa4d6b3b5fd5f179aa7456`, **with extensive uncommitted work**. That SHA alone does not reproduce the inspected state. No web source files, papers, local data, provider secrets or promotional artifacts were copied into this repository.

Inspected: web AGENTS/handoff/context map, current STATE and architecture ownership, Home library rendering, RightSidebar, annotation types, Classic CSS variables and Studio tokens. The local promotional library image was inspected as a historical visual aid, not treated as current behavior evidence. The native port is hand-written Swift; it does not embed the React app.

Web visual anchors: Classic text `#293B34`, forest accent `#284E40`, borders `#D9DFD3`; serif library/section headings with system sans controls; continue-reading card, clean library rows/grid and quiet note cards. The human's subsequent native direction uses one default Liquid Glass theme: subtle glass control groups, standard-material sidebars, opaque neutral light/charcoal cards, blue accents and system typography and solid Reduce Transparency/Increase Contrast fallbacks; Classic/Studio selection is removed. Native dark colors adapt to system appearance. Annotation colors remain yellow, green, blue and pink.

Mac adaptations: persistent NavigationSplitView sidebar; AppKit import/save panels and standard Settings window; resizable page navigator/PDF/inspector; keyboard menu commands and native text selection. No browser toolbar, account/profile page or web-service startup.

Asset provenance: [Icon-512.png](../Assets/Icon-512.png) is copied from the existing Folio web project's `public/icon-512.png` for the same user's native port. Build tooling derives the .icns locally. No new third-party fonts, illustrations or packages were introduced. A public distribution license has intentionally not been selected on the user's behalf.
