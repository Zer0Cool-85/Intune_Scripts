# Your branding assets

Put your logo and/or banner here and configure their relative paths in Config/Setup.json.

- Logo: PNG with transparency is preferred. Suggested source size: 600 x 160 pixels.
- Banner: JPG or PNG. Suggested source size: 1800 x 240 pixels.
- PNG, JPG, JPEG, and BMP are supported. SVG is not loaded directly by this WPF package.
- LogoPath and BannerPath can both be set, or both left empty.
- The logo fits proportionally within LogoMaxWidth and LogoMaxHeight.
- The banner fills its region and may crop at the edges. Keep text/logos away from edges.
- Image files are loaded from disk, not from the network. Paths are package-relative.

Example:

    "LogoPath": "Assets/company-logo.png",
    "BannerPath": "Assets/company-banner.jpg",
    "BannerHeight": 110

An empty image path hides that image. CompanyName and the welcome text still appear.
