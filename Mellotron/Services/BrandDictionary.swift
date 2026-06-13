import Foundation

/// A list of well-known product / company / tool names that Apple Speech
/// tends to lowercase or mis-case. Applied case-insensitively during
/// cleanup so users don't have to add them to their personal dictionary.
///
/// Order matters: longer entries come first so "Wispr Flow" beats "Wispr".
enum BrandDictionary {
    static let canonical: [String] = [
        // Mellotron itself
        "Mellotron",

        // AI assistants & products
        "Wispr Flow", "Wispr",
        "ChatGPT", "GPT-4", "GPT-5", "DALL·E",
        "Claude", "Claude.ai", "Anthropic",
        "Gemini", "Google Gemini", "Bard",
        "Perplexity", "Perplexity AI",
        "Copilot", "GitHub Copilot",
        "Llama", "Mistral", "DeepSeek",
        "Whisper", "Replit", "Cursor",

        // Apple platforms / frameworks
        "macOS", "iOS", "iPadOS", "watchOS", "tvOS", "visionOS",
        "iPhone", "iPad", "MacBook", "MacBook Pro", "MacBook Air", "iMac",
        "AirPods", "Vision Pro", "Apple Silicon",
        "AppKit", "SwiftUI", "UIKit", "Foundation", "Combine",
        "Xcode", "TestFlight", "App Store", "iCloud", "iMessage",
        "Apple Notes", "Apple Mail", "Safari",
        "Siri", "Spotlight",

        // Dev tools & languages
        "Swift", "Objective-C", "Objective C",
        "JavaScript", "TypeScript", "Python", "Rust", "Go", "Kotlin",
        "Node.js", "npm", "pnpm", "yarn", "Bun", "Deno",
        "React", "Next.js", "Vue", "Svelte", "Angular", "Astro", "Remix",
        "Tailwind", "Tailwind CSS",
        "GitHub", "GitLab", "Bitbucket", "VS Code", "Visual Studio Code",
        "JetBrains", "IntelliJ", "PyCharm", "WebStorm",
        "Docker", "Kubernetes", "Terraform",

        // Productivity
        "Google Docs", "Google Drive", "Google Sheets", "Google Slides",
        "Google Calendar", "Gmail", "YouTube",
        "Slack", "Notion", "Linear", "Figma", "Loom",
        "Zoom", "Microsoft Teams", "Microsoft Word", "Microsoft Excel",
        "Outlook", "OneDrive",
        "Discord", "Telegram", "WhatsApp",

        // Cloud / data
        "AWS", "Amazon Web Services", "S3", "EC2", "Lambda",
        "GCP", "Google Cloud", "Azure",
        "Vercel", "Netlify", "Cloudflare", "Supabase", "Firebase",
        "MongoDB", "PostgreSQL", "Postgres", "MySQL", "Redis",

        // Browsers / OSes
        "Google Chrome", "Microsoft Edge", "Firefox", "Arc",
        "Windows", "Linux", "Ubuntu",

        // Misc tech
        "Raycast", "Stripe", "Shopify", "OpenAI", "Hugging Face",
        "Twitter", "X.com", "LinkedIn", "Instagram", "TikTok",
        "Reddit", "Wikipedia", "Spotify", "Apple Music", "Netflix",

        // Universities & schools (Apple Speech consistently lowercases these)
        "McGill", "McGill University",
        "MIT", "Massachusetts Institute of Technology",
        "Stanford", "Stanford University",
        "Harvard", "Harvard University",
        "Yale", "Princeton", "Cornell", "Brown", "Dartmouth", "Columbia",
        "Carnegie Mellon", "CMU",
        "UPenn", "Penn", "University of Pennsylvania",
        "UC Berkeley", "Berkeley", "UCLA", "USC",
        "Georgia Tech", "Caltech",
        "NYU", "Northwestern", "Northeastern", "Duke",
        "Johns Hopkins", "JHU",
        "UT Austin", "UIUC", "Purdue", "Michigan",
        "Waterloo", "University of Waterloo",
        "Toronto", "University of Toronto", "UofT",
        "UBC", "Queen's University", "McMaster", "Western",
        "Oxford", "Cambridge", "Imperial College", "UCL", "LSE",
        "ETH", "ETH Zürich", "EPFL",

        // Engineering / student teams (proper nouns the LLM should catch)
        "Formula SAE", "Formula Electric", "Formula 1", "Formula E",
        "Baja SAE", "Solar Car", "Hyperloop", "RoboCup", "RoboSub",
        "NASA", "SpaceX", "Tesla", "Rivian", "Lucid",

        // Common Canadian / international companies
        "Shopify", "RBC", "TD Bank", "Bombardier", "Magna",
    ]
}
