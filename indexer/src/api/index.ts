import { db } from "ponder:api";
import schema from "ponder:schema";
import { Hono } from "hono";
import { graphql } from "ponder";

const app = new Hono();

app.use("/graphql", graphql({ db, schema }));

app.get("/", (c) => {
  return c.text("Meridian Indexer — visit /graphql for GraphQL playground");
});

export default app;
