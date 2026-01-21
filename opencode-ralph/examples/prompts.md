# Ralph Prompts Collection

A collection of effective Ralph prompts for various tasks.

## Quick Start

```bash
opencode run --agent ralph "Your prompt here"
```

Or use the CLI:

```bash
ralph "Your prompt here" --max-iterations 20
```

## Basic Prompts

### Simple Task

```
Create a file called greeting.txt with:
"Hello, Ralph!"

Output <promise>COMPLETE</promise> when the file exists and contains the correct text.
```

### File Modification

```
Add error handling to src/utils.ts:
1. Wrap all async functions in try-catch
2. Add proper error messages
3. Log errors to console.error

Run tests after changes. Output <promise>DONE</promise> when tests pass.
```

## Development Tasks

### REST API

```
Build a REST API for managing todos with:

## Endpoints
- GET /todos - List all todos
- POST /todos - Create todo
- PUT /todos/:id - Update todo  
- DELETE /todos/:id - Delete todo

## Requirements
- Use Express.js with TypeScript
- Implement input validation
- Add unit tests for each endpoint (>90% coverage)
- Include error handling

Output <promise>COMPLETE</promise> when all tests pass.
```

### React Component

```
Create a Button component in src/components/Button.tsx with:

## Props
- variant: 'primary' | 'secondary' | 'danger'
- size: 'small' | 'medium' | 'large'
- disabled: boolean
- onClick: () => void
- children: ReactNode

## Requirements
1. TypeScript with proper types
2. CSS-in-JS styling
3. Accessibility (ARIA attributes)
4. Unit tests with Jest
5. Storybook story

Output <promise>DONE</promise> when component and tests are ready.
```

### Database Migration

```
Create a database migration for adding user profiles:

## Table: users
- Add columns:
  - bio: TEXT
  - avatar_url: VARCHAR(500)
  - timezone: VARCHAR(50), default 'UTC'
  - updated_at: TIMESTAMP

## Requirements
1. Use Knex.js migrations
2. Write down migration
3. Write rollback migration
4. Add type definitions
5. Write tests for the new columns

Output <promise>COMPLETE</promise> when migrations run successfully.
```

## Refactoring Tasks

### Extract Function

```
Refactor src/services/payment.ts:

## Issues to fix
1. extractValidatePayment() function
2. extractProcessPayment() function  
3. extractSendConfirmation() function

## Requirements
- Each function < 50 lines
- Pure functions where possible
- Add JSDoc comments
- Add unit tests
- All existing tests still pass

Output <promise>DONE</promise> when refactoring complete and tests pass.
```

### Performance Optimization

```
Optimize src/api/search.ts for performance:

## Current Issues
- N+1 query problem
- Missing database indexes
- No caching

## Requirements
1. Fix N+1 queries with eager loading
2. Add database indexes for search fields
3. Add Redis caching (mock for now)
4. Add performance tests
5. Ensure no regression

Output <promise>OPTIMIZED</promise> when performance improved.
```

## Infrastructure Tasks

### Docker Setup

```
Set up Docker for the application:

## Requirements
1. Create Dockerfile (multi-stage build)
2. Create docker-compose.yml with:
   - App service
   - PostgreSQL
   - Redis
3. Create .dockerignore
4. Add health checks
5. Document usage

Output <promise>DONE</promise> when Docker setup works.
```

### CI/CD Pipeline

```
Create GitHub Actions workflow for:

## Workflow Steps
1. Install dependencies
2. Run linter
3. Run type check
4. Run tests
5. Build Docker image
6. Push to registry (conditional)

## Requirements
- Use matrix for Node versions
- Cache dependencies
- Fail fast on errors
- Add badge to README

Output <promise>COMPLETE</promise> when workflow runs successfully.
```

## Testing Tasks

### Add Tests

```
Add tests to src/utils/date.ts:

## Functions to test
- formatDate()
- parseDate()
- relativeTime()
- isValidDate()

## Requirements
1. Jest test file
2. Edge cases coverage
3. >95% coverage
4. Mock date/time where needed

Output <promise>TESTED</promise> when all functions tested.
```

### Fix Failing Tests

```
Fix the failing tests in tests/api/users.test.ts:

## Current Status
- 3 tests failing
- 2 tests skipped

## Requirements
1. Fix the failing tests
2. Unskip skipped tests
3. All tests must pass
4. Document why they failed

Output <promise>FIXED</promise> when all tests pass.
```

## Documentation Tasks

### README

```
Create comprehensive README.md for the project:

## Sections Required
1. Overview
2. Installation
3. Usage
4. Configuration
5. API Documentation
6. Contributing
7. License

## Requirements
- Use Markdown
- Include code examples
- Add badges for CI, coverage
- Document environment variables

Output <promise>DONE</prompt> when README is complete.
```

### API Documentation

```
Create OpenAPI documentation for the REST API:

## Endpoints to Document
- GET /users
- POST /users
- GET /users/:id
- PUT /users/:id
- DELETE /users/:id

## Requirements
1. OpenAPI 3.0 format
2. Request/response schemas
3. Status codes
4. Examples
5. Validation rules

Output <promise>DOCUMENTED</promise> when documentation is complete.
```

## Tips for Effective Prompts

### ✅ Do

- Be specific about requirements
- Include verification steps
- Set clear completion criteria
- Use <promise>TAG</promise> for signaling
- Specify test coverage targets
- Break complex tasks into steps

### ❌ Don't

- Use vague language
- Skip verification steps
- Have unclear success criteria
- Forget to mention testing
- Make tasks too large
- Omit context when needed

## Advanced Patterns

### Conditional Logic

```
Build authentication system with:

## Conditions
- If user is new: create account and send welcome
- If user exists: update last login
- If credentials invalid: return 401
- If account locked: return 403

Output <promise>AUTH_READY</promise> when all flows work.
```

### Iterative Enhancement

```
Enhance the existing todo app:

## Iteration 1: Basic CRUD
## Iteration 2: Add pagination
## Iteration 3: Add filtering
## Iteration 4: Add sorting

Output <promise>COMPLETE</promise> when all iterations are done.
```

## Troubleshooting

### Agent Stuck

If Ralph seems stuck:

```bash
# Add context
ralph --add-context "Try a different approach: ..."

# Or check what's happening
ralph --status
```

### Poor Results

If results are not good:

1. Make prompt more specific
2. Add more context
3. Break into smaller tasks
4. Specify expected patterns
5. Add examples

### Too Many Iterations

Set reasonable limits:

```bash
ralph "Your task" --max-iterations 10
```