import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, HashRouter } from "react-router-dom";
import App from "./App";
import "./styles.css";
import { isDesktopRuntime } from "./storage";
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    {isDesktopRuntime() ? <HashRouter><App /></HashRouter> : <BrowserRouter><App /></BrowserRouter>}
  </React.StrictMode>,
);
