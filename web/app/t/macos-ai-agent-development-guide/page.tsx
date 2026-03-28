import type { Metadata } from "next";
import { CTAButton } from "@/components/cta-button";

export const metadata: Metadata = {
  title: "Building macOS AI Agents: Lessons from Simplifying Agent Code with Better Models",
  description:
    "Practical lessons from building a macOS AI agent — how better LLMs like Claude Opus let you delete scaffolding code, and when to simplify vs when to keep guardrails.",
  openGraph: {
    title: "Building macOS AI Agents: Simplifying with Better Models",
    description:
      "How better LLMs let you delete hundreds of lines of retry logic, context management, and guardrail code from your agent.",
    type: "article",
    url: "https://fazm.ai/t/macos-ai-agent-development-guide",
  },
  twitter: {
    card: "summary_large_image",
    title: "Building macOS AI Agents: Simplifying with Better Models",
    description:
      "How better LLMs let you delete scaffolding code from your agent.",
  },
};

export default function MacOSAIAgentGuide() {
  return (
    <article className="max-w-3xl mx-auto px-6 py-16">
      {/* Hero */}
      <header className="mb-12">
        <h1 className="text-4xl font-bold tracking-tight mb-4">
          Building macOS AI Agents: Lessons from Simplifying Agent Code with
          Better Models
        </h1>
        <p className="text-lg text-gray-600">
          When the model gets smarter, your agent code should get simpler. But
          knowing what to delete — and what to keep — is the hard part.
        </p>
      </header>

      {/* TOC */}
      <nav className="bg-gray-50 rounded-lg p-6 mb-12">
        <h2 className="text-sm font-semibold uppercase text-gray-500 mb-3">
          Contents
        </h2>
        <ol className="space-y-2 text-blue-600">
          <li><a href="#scaffolding" className="hover:underline">1. The Scaffolding Problem in Agent Development</a></li>
          <li><a href="#what-to-delete" className="hover:underline">2. What You Can Delete When Models Improve</a></li>
          <li><a href="#what-to-keep" className="hover:underline">3. What You Should Never Delete</a></li>
          <li><a href="#macos-specific" className="hover:underline">4. macOS-Specific Agent Architecture</a></li>
          <li><a href="#accessibility" className="hover:underline">5. Accessibility APIs vs Screenshots</a></li>
          <li><a href="#model-selection" className="hover:underline">6. Choosing the Right Model for Your Agent</a></li>
          <li><a href="#discipline" className="hover:underline">7. The Discipline to Simplify</a></li>
        </ol>
      </nav>

      {/* Section 1 */}
      <section id="scaffolding" className="mb-12">
        <h2 className="text-2xl font-bold mb-4">
          1. The Scaffolding Problem in Agent Development
        </h2>
        <p className="text-gray-700 mb-4">
          Every AI agent starts the same way: you pick a model, wire up some
          tools, and start testing. Within hours you&apos;re adding retry logic.
          Within days, you&apos;ve built a context management layer. Within
          weeks, you have hundreds of lines of code whose only job is
          compensating for the model&apos;s weaknesses.
        </p>
        <p className="text-gray-700 mb-4">
          This scaffolding is necessary — until it isn&apos;t. When you
          upgrade from a weaker model to a stronger one, much of that
          compensating code becomes dead weight. It still runs, it still
          costs tokens in prompts, and it can actually hurt performance by
          over-constraining a model that doesn&apos;t need the guardrails.
        </p>
        <div className="bg-yellow-50 border-l-4 border-yellow-500 p-4 rounded">
          <p className="text-gray-800">
            <strong>Real example:</strong> One team building a macOS agent
            reported deleting over 300 lines of retry logic and context
            management code after switching from a mid-tier model to Claude
            Opus. The agent performed better with less code because the model
            handled edge cases that previously needed explicit handling.
          </p>
        </div>
      </section>

      {/* Section 2 */}
      <section id="what-to-delete" className="mb-12">
        <h2 className="text-2xl font-bold mb-4">
          2. What You Can Delete When Models Improve
        </h2>
        <p className="text-gray-700 mb-4">
          Not all scaffolding is created equal. Here&apos;s what typically
          becomes unnecessary with stronger models:
        </p>
        <ul className="list-disc pl-6 space-y-3 text-gray-700 mb-4">
          <li>
            <strong>Retry loops with error classification</strong> — weaker
            models fail on tool calls ~15-20% of the time. Stronger models drop
            this to &lt;2%. Your 50-line retry-with-backoff handler can become a
            simple single retry.
          </li>
          <li>
            <strong>Output format enforcement</strong> — parsing logic that
            extracts JSON from markdown code blocks, strips trailing commas,
            fixes missing quotes. Better models just output valid JSON.
          </li>
          <li>
            <strong>Context window management</strong> — summarization chains
            that compress history to fit context limits. Larger context windows
            and better attention mean you can often just pass the raw context.
          </li>
          <li>
            <strong>Step-by-step decomposition prompts</strong> —
            &quot;First analyze the screen. Then identify the target element.
            Then plan your action.&quot; Stronger models do this reasoning
            internally without explicit chain-of-thought prompting.
          </li>
          <li>
            <strong>Validation layers</strong> — checking that the model&apos;s
            tool calls have valid parameters before executing them. If the model
            reliably generates correct parameters, the validation is overhead.
          </li>
        </ul>
      </section>

      {/* Section 3 */}
      <section id="what-to-keep" className="mb-12">
        <h2 className="text-2xl font-bold mb-4">
          3. What You Should Never Delete
        </h2>
        <p className="text-gray-700 mb-4">
          Some code looks like scaffolding but is actually load-bearing:
        </p>
        <ul className="list-disc pl-6 space-y-3 text-gray-700 mb-4">
          <li>
            <strong>Safety boundaries</strong> — permission checks,
            confirmation prompts for destructive actions, rate limits on
            external APIs. These protect against model errors that will always
            happen, no matter how good the model gets.
          </li>
          <li>
            <strong>Logging and observability</strong> — you need to debug
            failures in production. Never delete structured logging just because
            failures are rarer.
          </li>
          <li>
            <strong>Timeout handling</strong> — API calls hang, processes stall,
            UI elements don&apos;t appear. This isn&apos;t about model quality,
            it&apos;s about real-world reliability.
          </li>
          <li>
            <strong>User feedback loops</strong> — showing the user what the
            agent is doing and letting them intervene. Trust but verify.
          </li>
        </ul>
      </section>

      {/* Section 4 */}
      <section id="macos-specific" className="mb-12">
        <h2 className="text-2xl font-bold mb-4">
          4. macOS-Specific Agent Architecture
        </h2>
        <p className="text-gray-700 mb-4">
          Building agents for macOS comes with unique advantages and
          constraints. The platform offers powerful APIs that most agent
          frameworks ignore:
        </p>
        <div className="overflow-x-auto mb-4">
          <table className="w-full border-collapse border border-gray-200">
            <thead>
              <tr className="bg-gray-50">
                <th className="border border-gray-200 px-4 py-2 text-left">macOS API</th>
                <th className="border border-gray-200 px-4 py-2 text-left">What It Gives Your Agent</th>
                <th className="border border-gray-200 px-4 py-2 text-left">Reliability</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">Accessibility (AX) APIs</td>
                <td className="border border-gray-200 px-4 py-2">Full UI tree of any app — buttons, text fields, labels with exact coordinates</td>
                <td className="border border-gray-200 px-4 py-2">Very high — system-level, no rendering variance</td>
              </tr>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">ScreenCaptureKit</td>
                <td className="border border-gray-200 px-4 py-2">Efficient screen capture with window-level filtering</td>
                <td className="border border-gray-200 px-4 py-2">High — hardware-accelerated</td>
              </tr>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">CGEvent / IOHIDEvent</td>
                <td className="border border-gray-200 px-4 py-2">Synthetic mouse/keyboard events at the system level</td>
                <td className="border border-gray-200 px-4 py-2">Very high — bypasses app-level input handling</td>
              </tr>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">NSWorkspace</td>
                <td className="border border-gray-200 px-4 py-2">App launching, file handling, URL schemes</td>
                <td className="border border-gray-200 px-4 py-2">Very high — standard Cocoa API</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p className="text-gray-700">
          The key insight is that these APIs give your agent structured data
          about the screen state — not pixels to interpret, but actual UI
          elements with semantic meaning. This fundamentally changes the
          agent architecture from &quot;look at a screenshot and guess&quot; to
          &quot;read the UI tree and act precisely.&quot;
        </p>
      </section>

      {/* Section 5 */}
      <section id="accessibility" className="mb-12">
        <h2 className="text-2xl font-bold mb-4">
          5. Accessibility APIs vs Screenshots
        </h2>
        <p className="text-gray-700 mb-4">
          This is the single biggest architectural decision in desktop agent
          development. The two approaches have dramatically different
          trade-offs:
        </p>
        <div className="overflow-x-auto mb-4">
          <table className="w-full border-collapse border border-gray-200">
            <thead>
              <tr className="bg-gray-50">
                <th className="border border-gray-200 px-4 py-2 text-left">Factor</th>
                <th className="border border-gray-200 px-4 py-2 text-left">Accessibility APIs</th>
                <th className="border border-gray-200 px-4 py-2 text-left">Screenshot + Vision</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">Click accuracy</td>
                <td className="border border-gray-200 px-4 py-2">~99% (exact coordinates from UI tree)</td>
                <td className="border border-gray-200 px-4 py-2">~80-90% (estimated from pixels)</td>
              </tr>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">Speed</td>
                <td className="border border-gray-200 px-4 py-2">~50ms to read UI tree</td>
                <td className="border border-gray-200 px-4 py-2">~2-5s per screenshot + inference</td>
              </tr>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">Token cost</td>
                <td className="border border-gray-200 px-4 py-2">Low (text-only UI tree)</td>
                <td className="border border-gray-200 px-4 py-2">High (image tokens expensive)</td>
              </tr>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">Dynamic content</td>
                <td className="border border-gray-200 px-4 py-2">Handles well (reads current state)</td>
                <td className="border border-gray-200 px-4 py-2">Can miss updates between captures</td>
              </tr>
              <tr>
                <td className="border border-gray-200 px-4 py-2 font-medium">Platform support</td>
                <td className="border border-gray-200 px-4 py-2">macOS, Windows (different APIs)</td>
                <td className="border border-gray-200 px-4 py-2">Any platform with screen access</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p className="text-gray-700">
          The practical difference is enormous. An accessibility-based agent can
          interact with a complex form in 2-3 seconds. A screenshot-based agent
          needs 15-30 seconds for the same task and may fail on tricky UI
          elements like dropdown menus or overlapping modals.
        </p>
      </section>

      {/* Section 6 */}
      <section id="model-selection" className="mb-12">
        <h2 className="text-2xl font-bold mb-4">
          6. Choosing the Right Model for Your Agent
        </h2>
        <p className="text-gray-700 mb-4">
          Model choice for agents is different from model choice for chatbots.
          Agents need:
        </p>
        <ul className="list-disc pl-6 space-y-2 text-gray-700 mb-4">
          <li><strong>Reliable tool calling</strong> — generating valid JSON parameters every time</li>
          <li><strong>Multi-step reasoning</strong> — planning 3-5 actions ahead without losing track</li>
          <li><strong>Error recovery</strong> — recognizing when an action failed and adapting</li>
          <li><strong>Context utilization</strong> — using all the information provided, not just the last message</li>
        </ul>
        <p className="text-gray-700 mb-4">
          In practice, the top-tier models (Claude Opus, GPT-4o) produce
          dramatically simpler agent code. The mid-tier models (Sonnet, GPT-4o
          mini) need more scaffolding but cost 5-10x less per token. The
          trade-off isn&apos;t just token cost — it&apos;s engineering time
          spent building and maintaining compensating code.
        </p>
        <p className="text-gray-700">
          For most teams, starting with the strongest model and simplifying your
          codebase, then selectively downgrading specific tasks to cheaper
          models, is more efficient than building complex scaffolding around a
          weaker model from day one.
        </p>
      </section>

      {/* Section 7 */}
      <section id="discipline" className="mb-12">
        <h2 className="text-2xl font-bold mb-4">
          7. The Discipline to Simplify
        </h2>
        <p className="text-gray-700 mb-4">
          The hardest part of improving your agent isn&apos;t adding features.
          It&apos;s removing code that works but is no longer necessary. Every
          developer feels the pull: &quot;This retry logic took me two days to
          build and it works perfectly. Why would I delete it?&quot;
        </p>
        <p className="text-gray-700 mb-4">
          Because unnecessary code has costs even when it works:
        </p>
        <ul className="list-disc pl-6 space-y-2 text-gray-700 mb-4">
          <li>Extra tokens in system prompts describing the retry behavior</li>
          <li>Latency from validation checks that always pass</li>
          <li>Cognitive load for anyone reading the codebase</li>
          <li>Surface area for bugs when you change something else</li>
        </ul>
        <p className="text-gray-700">
          The best agent developers run a regular &quot;scaffolding audit&quot;
          — testing each piece of compensating code with the current model to
          see if it&apos;s still needed. If removing it doesn&apos;t change the
          success rate, it goes.
        </p>
      </section>

      {/* CTA */}
      <section className="bg-gradient-to-r from-blue-600 to-blue-800 rounded-2xl p-8 text-center text-white">
        <h2 className="text-2xl font-bold mb-3">
          See a macOS agent built on these principles
        </h2>
        <p className="text-blue-100 mb-6">
          Fazm is an open-source macOS AI agent using accessibility APIs for
          reliable desktop automation. Clean codebase, no unnecessary
          scaffolding. Free to use.
        </p>
        <CTAButton href="https://github.com/m13v/fazm" page="/t/macos-ai-agent-development-guide">
          Explore the Source Code
        </CTAButton>
      </section>

      {/* Footer */}
      <footer className="mt-16 pt-8 border-t border-gray-200 text-center text-sm text-gray-500">
        <p>
          <a href="https://fazm.ai" className="hover:underline">fazm.ai</a>{" "}
          — Open-source desktop AI agent for macOS
        </p>
      </footer>
    </article>
  );
}
