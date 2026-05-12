# why PascalCase for required module variable names?

Since they act like namespaces, and namespaces are typically PascalCase, it makes sense to use PascalCase for required module variable names as well. (similar to `import * as Namespace from 'module'` in JavaScript/TypeScript)

This helps to visually distinguish them from regular variables and functions, which are typically camelCase.
