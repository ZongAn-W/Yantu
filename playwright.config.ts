import { defineConfig, devices } from '@playwright/test';
import { fileURLToPath } from 'node:url';

// Keep the browser runtime with the D-drive workspace for repeatable local tests.
process.env.PLAYWRIGHT_BROWSERS_PATH ??= fileURLToPath(
  new URL('./.playwright-browsers', import.meta.url),
);

export default defineConfig({testDir:'./tests',fullyParallel:false,workers:1,timeout:30000,expect:{timeout:7000},reporter:[['list'],['html',{open:'never'}]],use:{baseURL:'http://127.0.0.1:5174',trace:'retain-on-failure'},projects:[{name:'desktop',use:{...devices['Desktop Chrome']}},{name:'mobile',use:{...devices['Pixel 7']}}],webServer:{command:'npm run dev -- --port 5174',url:'http://127.0.0.1:5174',reuseExistingServer:true,timeout:60000}});
