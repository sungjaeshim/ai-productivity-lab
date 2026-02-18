---
title: "Claude MCP Setup Guide 2026: Connect AI to Your Tools"
description: "Learn how to set up Claude Desktop with Model Context Protocol (MCP). Connect Claude to files, databases, APIs, and automate your workflow with this step-by-step guide."
pubDate: Feb 16 2026
heroImage: "https://images.unsplash.com/photo-1677442136019-21780ecad995?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w4NzEyNzZ8MHwxfHNlYXJjaHwxfHxBSSUyMGNvbm5lY3Rpb24lMjBuZXR3b3JrJTIwdGVjaG5vbG9neXxlbnwwfDB8fHwxNzA4MjAwMDAwfDA&ixlib=rb-4.1.0&q=80&w=1080"
heroImageAlt: "AI network connections visualization"
heroImageCredit: "Photo by <a href='https://unsplash.com/@deepmind'>DeepMind</a> on <a href='https://unsplash.com'>Unsplash</a>"
tags: ["Claude", "MCP", "AI Tools", "Automation", "Tutorial"]
---

## What is MCP?

Model Context Protocol (MCP) is Anthropic's open standard that lets Claude Desktop connect to external tools, files, and services. Think of it as USB ports for AI—plug in any compatible tool, and Claude can use it.

**Why this matters:**
- Claude can read your local files
- Execute code on your machine
- Query databases
- Call external APIs
- Automate repetitive tasks

## Prerequisites

Before we start, you'll need:

1. **Claude Desktop** (macOS or Windows)
2. **Node.js** v18+ or **Python** 3.10+
3. Basic terminal/command line knowledge
4. 10 minutes of setup time

## Step 1: Install Claude Desktop

Download Claude Desktop from [claude.ai/desktop](https://claude.ai/desktop):

- **macOS:** Download the `.dmg` file, drag to Applications
- **Windows:** Run the `.exe` installer

Sign in with your Anthropic account. Free tier works, but Pro ($20/month) gets you more messages.

## Step 2: Locate the Config File

MCP servers are configured in a JSON file:

| OS | Config Path |
|-----|------------|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |

Create the file if it doesn't exist:

```bash
# macOS
mkdir -p ~/Library/Application\ Support/Claude
touch ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

## Step 3: Add Your First MCP Server

Let's add the **filesystem** server so Claude can read/write files:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/yourname/Documents",
        "/Users/yourname/Projects"
      ]
    }
  }
}
```

**What this does:**
- `command`: Uses `npx` to run the server
- `args`: Specifies which directories Claude can access
- Replace paths with your actual directories

## Step 4: Restart Claude Desktop

After saving the config:

1. Quit Claude Desktop completely (Cmd+Q / Alt+F4)
2. Reopen the app
3. Look for the 🔌 icon in the input area—this confirms MCP is active

## Popular MCP Servers

Here are high-value MCP servers you can add:

### Brave Search (Web Search)

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@anthropics/mcp-brave-search"],
      "env": {
        "BRAVE_API_KEY": "your-api-key"
      }
    }
  }
}
```

Get a free API key at [brave.com/search/api](https://brave.com/search/api).

### GitHub (Repository Access)

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxx"
      }
    }
  }
}
```

Create a token at [github.com/settings/tokens](https://github.com/settings/tokens).

### SQLite (Database Queries)

```json
{
  "mcpServers": {
    "sqlite": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-sqlite",
        "/path/to/your/database.db"
      ]
    }
  }
}
```

### Memory (Persistent Context)

```json
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    }
  }
}
```

This lets Claude remember things across conversations.

## Complete Config Example

Here's a production-ready setup with multiple servers:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/yourname/Documents",
        "/Users/yourname/Projects"
      ]
    },
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@anthropics/mcp-brave-search"],
      "env": {
        "BRAVE_API_KEY": "YOUR_KEY"
      }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxx"
      }
    }
  }
}
```

## Troubleshooting

### "MCP server failed to start"

1. Check if Node.js is installed: `node --version`
2. Try running the command manually in terminal
3. Look at Claude Desktop logs:
   - macOS: `~/Library/Logs/Claude/`
   - Windows: `%APPDATA%\Claude\logs\`

### "Permission denied"

- Make sure directories in filesystem server exist
- On macOS, grant Full Disk Access to Claude in System Preferences

### Server not appearing

- Verify JSON syntax (use a JSON validator)
- Restart Claude Desktop after config changes

## Security Best Practices

MCP gives Claude real power on your machine. Stay safe:

1. **Limit directories:** Only expose folders you need
2. **Use read-only when possible:** Some servers support read-only mode
3. **Rotate API keys:** Don't use production credentials
4. **Review server source:** Check npm packages before installing

## What Can You Do With MCP?

Once configured, try these prompts:

- "Read my project's README and summarize it"
- "Search the web for Python best practices in 2026"
- "List all TODO comments in my codebase"
- "Query my SQLite database for user statistics"
- "Create a new file with today's meeting notes"

## Conclusion

MCP transforms Claude from a chat assistant into a genuine AI agent that can interact with your digital environment. The setup takes 10 minutes but unlocks hours of automation potential.

**Next steps:**
1. Start with filesystem access
2. Add one API integration (Brave or GitHub)
3. Experiment with prompts that use these tools
4. Build custom MCP servers for your specific workflows

---

*Updated February 2026. MCP is under active development—check [modelcontextprotocol.io](https://modelcontextprotocol.io) for the latest servers and documentation.*
