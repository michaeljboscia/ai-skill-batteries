---
name: mx-wp-content
description: Use when working with ACF Pro fields, Flexible Content, Repeater fields, Gutenberg blocks as data, or content modeling in headless WordPress with WPGraphQL. Also use when the user mentions 'ACF', 'Advanced Custom Fields', 'flexible content', 'repeater', 'field group', 'Gutenberg blocks GraphQL', or 'content blocks'.
---

# Headless WordPress Content Modeling — ACF Pro + WPGraphQL for AI Coding Agents

**Loads when modeling content with ACF Pro or querying Gutenberg blocks via WPGraphQL.**

## When to also load
- `mx-wp-core` — WPGraphQL setup, fetchGraphQL, codegen
- `mx-wp-perf` — repeater performance, query optimization
- `mx-wp-media` — image fields in ACF

---

## Level 1: ACF Field Groups for GraphQL (Beginner)

### 1.1 Enabling ACF Fields in GraphQL

Every ACF field group must explicitly opt into the GraphQL schema. Two requirements:

1. Install **WPGraphQL for ACF** plugin
2. Enable `show_in_graphql` per field group

**BAD — Field group invisible to GraphQL:**
```php
acf_add_local_field_group([
    'key'    => 'group_hero',
    'title'  => 'Hero Section',
    'fields' => [
        ['key' => 'field_headline', 'name' => 'headline', 'type' => 'text'],
    ],
    'location' => [[['param' => 'post_type', 'operator' => '==', 'value' => 'page']]],
]);
```

**GOOD — Explicitly exposed to GraphQL:**
```php
acf_add_local_field_group([
    'key'                => 'group_hero',
    'title'              => 'Hero Section',
    'show_in_graphql'    => true,                // REQUIRED
    'graphql_field_name' => 'heroSection',       // camelCase
    'fields' => [
        ['key' => 'field_headline', 'name' => 'headline', 'type' => 'text'],
    ],
    'location' => [[['param' => 'post_type', 'operator' => '==', 'value' => 'page']]],
]);
```

### 1.2 ACF Naming Conventions

- ACF field names: `snake_case` (WPGraphQL auto-converts to camelCase)
- **Never repeat parent name in subfields**: `hero.hero_title` is redundant. Use `hero.headline`.
- **Describe purpose, not location**: `primary_cta` not `sidebar_button_top`

**BAD naming → verbose GraphQL:**
```graphql
query { page { heroSection { heroTitle, heroBackgroundImage } } }
```

**GOOD naming → clean GraphQL:**
```graphql
query { page { hero { headline, backgroundImage { node { sourceUrl } } } } }
```

---

## Level 2: Flexible Content + Repeaters (Intermediate)

### 2.1 Flexible Content in GraphQL

Flexible Content fields use **Union Types** in GraphQL. Query with **inline fragments** per layout.

**BAD — No type discrimination:**
```graphql
# FAILS: GraphQL doesn't know which fields belong to which layout
query { page { pageBuilder { layouts { headline, bodyContent } } } }
```

**GOOD — Inline fragments per layout type:**
```graphql
query GetPageLayouts($id: ID!) {
  page(id: $id, idType: DATABASE_ID) {
    pageBuilder {
      layouts {
        __typename
        ... on Page_Pagebuilder_Layouts_Hero {
          headline
          backgroundImage { node { sourceUrl, altText } }
        }
        ... on Page_Pagebuilder_Layouts_TextBlock {
          bodyContent
          textAlignment
        }
        ... on Page_Pagebuilder_Layouts_Gallery {
          images { node { sourceUrl, altText, mediaDetails { width, height } } }
        }
      }
    }
  }
}
```

### 2.2 Block-to-Component Mapping (Frontend)

Use `__typename` to route layouts to React components:

```tsx
const ComponentMap: Record<string, React.FC<any>> = {
  'Page_Pagebuilder_Layouts_Hero': HeroComponent,
  'Page_Pagebuilder_Layouts_TextBlock': TextBlockComponent,
  'Page_Pagebuilder_Layouts_Gallery': GalleryComponent,
}

function PageBuilder({ layouts }: { layouts: any[] }) {
  return (
    <>
      {layouts.map((block, i) => {
        const Component = ComponentMap[block.__typename]
        if (!Component) return <FallbackBlock key={i} data={block} />
        return <Component key={i} {...block} />
      })}
    </>
  )
}
```

### 2.3 Repeater Fields: The 50-Item Rule

ACF stores each repeater subfield as a separate `wp_postmeta` row. 5 subfields x 50 rows = 250 rows in postmeta.

| Dataset Size | Use | Why |
|-------------|-----|-----|
| < 20 items | ACF Repeater | Simple, fast enough |
| 20-50 items | ACF Repeater with pagination | Use ACF's built-in row pagination |
| > 50 items | **Custom Post Type** | Repeaters don't paginate in GraphQL, load entire array |

**BAD — 500 staff members in a repeater:**
```graphql
# Loads ALL 500 rows into memory. No pagination possible.
query { page(id: "about", idType: URI) {
  companyData { staffRepeater { name, position, bio, photo { node { sourceUrl } } } }
}}
```

**GOOD — Staff as a CPT with cursor pagination:**
```graphql
query GetStaff($after: String) {
  staffMembers(first: 20, after: $after) {
    pageInfo { hasNextPage, endCursor }
    nodes {
      title
      staffDetails { position, biography }
      featuredImage { node { sourceUrl } }
    }
  }
}
```

---

## Level 3: Gutenberg Blocks as Structured Data (Advanced)

### 3.1 Plugin Decision Tree

| Plugin | Approach | Best For |
|--------|----------|----------|
| WPGraphQL Content Blocks (Faust.js) | Strongly typed block nodes | Production headless sites |
| WPGraphQL Gutenberg (legacy) | `blocksJSON` raw JSON field | Legacy projects only |
| WP VIP Block Data API | Pure JSON, no HTML parsing | WordPress VIP hosted sites |

### 3.2 Querying Typed Blocks

```graphql
query GetStructuredBlocks($id: ID!) {
  post(id: $id, idType: SLUG) {
    editorBlocks {
      __typename
      ... on CoreParagraphBlock {
        attributes { content, dropCap, fontSize }
      }
      ... on CoreImageBlock {
        attributes { url, alt, width, height }
      }
      ... on CoreHeadingBlock {
        attributes { content, level }
      }
    }
  }
}
```

### 3.3 ACF Local JSON for Version Control

Store field groups as JSON files in your theme. Loads from files instead of DB — faster and version-controlled.

```
theme/
  acf-json/
    group_hero.json
    group_page_builder.json
```

---

## Performance: Make It Fast

- Use ACF Local JSON — loads from file, not DB
- Organize fields with Tabs to reduce admin page weight
- Audit unused fields regularly — orphaned meta entries bloat wp_postmeta
- For large repeater queries, consider `update_post_meta_cache => false`

## Observability: Know It's Working

- Test queries in GraphiQL IDE (WPGraphQL settings → enable IDE)
- After adding new ACF field groups, verify they appear in GraphQL schema via introspection
- Monitor for `null` returns on ACF fields — often means `show_in_graphql` is missing

---

## Enforcement: Anti-Rationalization Rules

### Rule 1: Never Generate PHP Templates
**You will be tempted to:** create `single.php` or `page.php` with WordPress loops.
**Why that fails:** In headless architecture, PHP templates are completely obsolete. WordPress only serves data via the GraphQL API.
**The right way:** Write GraphQL queries + React/Next.js components. Never generate PHP rendering code.

### Rule 2: Never Use get_field() in Frontend Code
**You will be tempted to:** call `get_field('hero_title')` to retrieve ACF data.
**Why that fails:** `get_field()` is a PHP function — it cannot run in Node.js or the browser. It only exists in WordPress PHP runtime.
**The right way:** Query ACF data exclusively via WPGraphQL.

### Rule 3: Never Forget show_in_graphql on Field Groups
**You will be tempted to:** register ACF fields and assume they're automatically in the GraphQL schema.
**Why that fails:** WPGraphQL for ACF uses strict opt-in. Missing `show_in_graphql => true` silently hides the entire field group from the API.
**The right way:** Always include `show_in_graphql => true` and `graphql_field_name` in every field group registration.

### Rule 4: Never Use Repeaters for Large Datasets
**You will be tempted to:** put 200+ items in an ACF Repeater "because it's easy."
**Why that fails:** Each subfield row creates a separate wp_postmeta entry. 200 rows x 5 fields = 1,000 DB rows. No GraphQL pagination. Loads everything into memory.
**The right way:** Use a Custom Post Type with WPGraphQL cursor pagination for datasets > 50 items.
