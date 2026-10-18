{{flutter_js}}
{{flutter_build_config}}

(() => {
  const startup = window.plannerStartup;
  startup?.stage('正在加载学习执行台', '正在准备页面内容，请稍候。');

  _flutter.loader.load({
    // The current SDK only updates existing workers to its unregistering worker.
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}},
    },
    config: {
      canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    },
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        startup?.stage('正在准备显示内容', '页面即将打开，请稍候。');
        const appRunner = await engineInitializer.initializeEngine();
        startup?.stage('正在打开工作台', '正在完成最后的准备。');
        await appRunner.runApp();
      } catch (error) {
        startup?.fail(error);
      }
    },
  }).catch((error) => startup?.fail(error));
})();
