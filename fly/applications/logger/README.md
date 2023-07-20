# logger

To install dependencies:

```bash
bun install
```

To run:

```bash
bun run index.ts
```

To deploy:

```
fly launch
fly secrets set ACCESS_TOKEN=$(fly auth token)
fly deploy --ha=false
```

This project was created using `bun init` in bun v0.6.13. [Bun](https://bun.sh) is a fast all-in-one JavaScript runtime.
