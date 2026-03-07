import { test, expect } from "@playwright/test";

test.describe("Homepage", () => {
  test("loads and shows walkthrough section", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("text=Demo Walkthrough")).toBeVisible();
    await expect(page.locator("text=Follow the guided walkthrough")).toBeVisible();
  });

  test("shows all 8 walkthrough steps", async ({ page }) => {
    await page.goto("/");
    for (let i = 1; i <= 8; i++) {
      await expect(page.locator(`text=${i}`).first()).toBeVisible();
    }
  });

  test("shows protocol architecture section", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("text=Protocol Architecture")).toBeVisible();
    await expect(page.getByText("FORGE", { exact: true })).toBeVisible();
    await expect(page.getByText("SHIELD", { exact: true })).toBeVisible();
    await expect(page.getByText("NEXUS", { exact: true })).toBeVisible();
  });

  test("shows core layers section with links", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("text=Core Protocol Layers")).toBeVisible();
    const forgeLink = page.locator('a[href="/forge"]').first();
    await expect(forgeLink).toBeVisible();
  });

  test("shows composability section", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("text=Composability & Automation")).toBeVisible();
    await expect(page.getByRole("heading", { name: "HedgeRouter" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "FlashRebalancer" })).toBeVisible();
  });

  test("shows tech stack section", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("text=Built With")).toBeVisible();
    await expect(page.locator("text=Solidity 0.8.27")).toBeVisible();
    await expect(page.locator("text=Foundry")).toBeVisible();
  });
});

test.describe("Forge - Vault List", () => {
  test("loads vault list page with demo vaults", async ({ page }) => {
    await page.goto("/forge");
    await expect(page.locator("text=Structured Credit Vaults")).toBeVisible();
    await expect(page.locator("text=Vault #0")).toBeVisible();
    await expect(page.locator("text=Vault #1")).toBeVisible();
  });

  test("vault cards show status badges", async ({ page }) => {
    await page.goto("/forge");
    const activeBadges = page.locator("text=Active");
    await expect(activeBadges.first()).toBeVisible();
  });

  test("clicking vault navigates to detail page", async ({ page }) => {
    await page.goto("/forge");
    await page.locator("text=Vault #0").first().click();
    await page.waitForURL("**/forge/0");
    await expect(page.locator("text=Vault #0")).toBeVisible();
  });
});

test.describe("Forge - Vault Detail", () => {
  test("shows vault metrics", async ({ page }) => {
    await page.goto("/forge/0");
    await expect(page.locator("text=Vault #0")).toBeVisible();
    await expect(page.locator("text=Total Deposited")).toBeVisible();
    await expect(page.locator("text=Yield Received")).toBeVisible();
    await expect(page.locator("text=Yield Distributed")).toBeVisible();
  });

  test("shows all three tranches", async ({ page }) => {
    await page.goto("/forge/0");
    await expect(page.locator("text=Senior")).toBeVisible();
    await expect(page.locator("text=Mezzanine")).toBeVisible();
    await expect(page.locator("text=Equity")).toBeVisible();
  });

  test("tranches show target APR and allocation", async ({ page }) => {
    await page.goto("/forge/0");
    await expect(page.locator("text=Target APR").first()).toBeVisible();
    await expect(page.locator("text=Allocation").first()).toBeVisible();
    await expect(page.locator("text=Total Invested").first()).toBeVisible();
  });

  test("shows invest/claim/withdraw action buttons", async ({ page }) => {
    await page.goto("/forge/0");
    await expect(page.locator("text=Invest").first()).toBeVisible();
    await expect(page.locator("text=Claim").first()).toBeVisible();
    await expect(page.locator("text=Withdraw").first()).toBeVisible();
  });

  test("clicking Invest shows amount input", async ({ page }) => {
    await page.goto("/forge/0");
    await page.locator("text=Invest").first().click();
    await expect(page.locator('input[placeholder="Amount"]').first()).toBeVisible();
  });

  test("shows waterfall trigger button", async ({ page }) => {
    await page.goto("/forge/0");
    await expect(page.locator("text=Trigger Waterfall Distribution")).toBeVisible();
  });

  test("back link navigates to forge list", async ({ page }) => {
    await page.goto("/forge/0");
    await page.locator("text=Back").click();
    await page.waitForURL("**/forge");
  });
});

test.describe("Shield - CDS List", () => {
  test("loads CDS list page", async ({ page }) => {
    await page.goto("/shield");
    await expect(page.locator("text=Credit Default Swaps")).toBeVisible();
    await expect(page.locator("text=CDS #0")).toBeVisible();
  });

  test("shows CDS status badges", async ({ page }) => {
    await page.goto("/shield");
    const activeBadges = page.locator("text=Active");
    await expect(activeBadges.first()).toBeVisible();
  });

  test("clicking CDS navigates to detail page", async ({ page }) => {
    await page.goto("/shield");
    await page.locator("text=CDS #0").first().click();
    await page.waitForURL("**/shield/0");
    await expect(page.locator("text=CDS #0")).toBeVisible();
  });
});

test.describe("Shield - CDS Detail", () => {
  test("shows CDS info grid", async ({ page }) => {
    await page.goto("/shield/0");
    await expect(page.locator("text=CDS #0")).toBeVisible();
    await expect(page.locator("text=Protection Amount")).toBeVisible();
    await expect(page.locator("text=Premium Rate")).toBeVisible();
    await expect(page.locator("text=Maturity")).toBeVisible();
  });

  test("shows buyer and seller info", async ({ page }) => {
    await page.goto("/shield/0");
    await expect(page.locator("text=Protection Buyer")).toBeVisible();
    await expect(page.locator("text=Protection Seller")).toBeVisible();
  });

  test("shows action buttons for active CDS", async ({ page }) => {
    await page.goto("/shield/0");
    await expect(page.locator("text=Actions")).toBeVisible();
  });
});

test.describe("Pools - List", () => {
  test("loads pool list page with demo pools", async ({ page }) => {
    await page.goto("/pools");
    await expect(page.locator("text=CDS AMM Pools")).toBeVisible();
    await expect(page.locator("text=Pool #0")).toBeVisible();
    await expect(page.locator("text=Pool #1")).toBeVisible();
  });

  test("clicking pool navigates to detail page", async ({ page }) => {
    await page.goto("/pools");
    await page.locator("text=Pool #0").first().click();
    await page.waitForURL("**/pools/0");
    await expect(page.locator("text=CDS AMM Pool #0")).toBeVisible();
  });
});

test.describe("Pools - Detail", () => {
  test("shows pool metrics", async ({ page }) => {
    await page.goto("/pools/0");
    await expect(page.getByRole("heading", { name: "CDS AMM Pool #0" })).toBeVisible();
    await expect(page.locator("text=Total Liquidity")).toBeVisible();
    await expect(page.locator("text=Protection Sold")).toBeVisible();
    await expect(page.locator("text=Current Spread")).toBeVisible();
    await expect(page.locator("text=Utilization").first()).toBeVisible();
  });

  test("shows utilization gauge", async ({ page }) => {
    await page.goto("/pools/0");
    await expect(page.locator("text=Pool Utilization")).toBeVisible();
  });

  test("shows pool terms", async ({ page }) => {
    await page.goto("/pools/0");
    await expect(page.locator("text=Pool Terms")).toBeVisible();
    await expect(page.locator("text=Base Spread")).toBeVisible();
    await expect(page.locator("text=Curve Slope")).toBeVisible();
  });

  test("shows deposit form", async ({ page }) => {
    await page.goto("/pools/0");
    await expect(page.locator("text=Provide Liquidity")).toBeVisible();
    await expect(page.locator('input[placeholder="Amount to deposit"]')).toBeVisible();
  });

  test("shows withdraw form", async ({ page }) => {
    await page.goto("/pools/0");
    await expect(page.locator("text=Withdraw Liquidity")).toBeVisible();
    await expect(page.locator('input[placeholder="Shares to withdraw"]')).toBeVisible();
  });

  test("shows buy protection form for active pool", async ({ page }) => {
    await page.goto("/pools/0");
    await expect(page.getByRole("heading", { name: "Buy Protection" })).toBeVisible();
    await expect(page.locator('input[placeholder="Protection notional"]')).toBeVisible();
  });

  test("deposit button is disabled when empty", async ({ page }) => {
    await page.goto("/pools/0");
    const depositBtn = page.locator("button", { hasText: "Deposit" });
    await expect(depositBtn).toBeDisabled();
  });

  test("deposit button enables when amount entered", async ({ page }) => {
    await page.goto("/pools/0");
    await page.locator('input[placeholder="Amount to deposit"]').fill("1000");
    const depositBtn = page.locator("button", { hasText: /Deposit|Approve/ });
    await expect(depositBtn).toBeEnabled();
  });
});

test.describe("Nexus", () => {
  test("shows connect wallet prompt when not connected", async ({ page }) => {
    await page.goto("/nexus");
    await expect(page.locator("text=Connect Wallet").first()).toBeVisible();
  });
});

test.describe("Strategies", () => {
  test("loads strategies page with demo strategies", async ({ page }) => {
    await page.goto("/strategies");
    await expect(page.getByRole("heading", { name: "Yield Strategies" })).toBeVisible();
    await expect(page.locator("text=Conservative Senior")).toBeVisible();
    await expect(page.locator("text=Balanced Growth")).toBeVisible();
    await expect(page.locator("text=High Yield Alpha")).toBeVisible();
  });
});

test.describe("Analytics", () => {
  test("loads analytics page", async ({ page }) => {
    await page.goto("/analytics");
    // Analytics page may show loading state since it reads from blockchain
    await expect(page.locator("text=Loading protocol analytics").or(page.locator("text=Protocol Overview"))).toBeVisible();
  });
});

test.describe("Navigation", () => {
  test("navigation links work", async ({ page }) => {
    await page.goto("/");

    // Navigate to Forge
    await page.locator('a[href="/forge"]').first().click();
    await page.waitForURL("**/forge");
    await expect(page.locator("text=Structured Credit Vaults")).toBeVisible();

    // Navigate to Shield
    await page.locator('a[href="/shield"]').first().click();
    await page.waitForURL("**/shield");
    await expect(page.locator("text=Credit Default Swaps")).toBeVisible();

    // Navigate to Pools
    await page.locator('a[href="/pools"]').first().click();
    await page.waitForURL("**/pools");
    await expect(page.locator("text=CDS AMM Pools")).toBeVisible();
  });

  test("header shows Fuji badge", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("text=Fuji").first()).toBeVisible();
  });
});

test.describe("404 / Not Found", () => {
  test("non-existent vault shows not found", async ({ page }) => {
    await page.goto("/forge/999");
    await expect(page.locator("text=Vault not found")).toBeVisible();
  });

  test("non-existent pool shows not found", async ({ page }) => {
    await page.goto("/pools/999");
    await expect(page.locator("text=Pool Not Found")).toBeVisible();
  });

  test("non-existent CDS shows not found", async ({ page }) => {
    await page.goto("/shield/999");
    await expect(page.locator("text=CDS contract not found")).toBeVisible();
  });
});

test.describe("No console errors on key pages", () => {
  for (const path of ["/", "/forge", "/forge/0", "/shield", "/shield/0", "/pools", "/pools/0", "/strategies", "/analytics"]) {
    test(`${path} loads without JS errors`, async ({ page }) => {
      const errors: string[] = [];
      page.on("pageerror", (err) => errors.push(err.message));
      await page.goto(path);
      await page.waitForTimeout(2000);
      expect(errors).toEqual([]);
    });
  }
});
