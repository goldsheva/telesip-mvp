enum Environment { dev, preprod, prod }

class EnvConfig {
  static Environment env = Environment.prod;

  static void init(Environment environment) {
    env = environment;
  }

  static String get baseApiUrl {
    switch (env) {
      case Environment.dev:
        return 'https://teleleo.k8s-stage.bringo.tel/react_api';
      case Environment.preprod:
        return 'https://teleleo-pp.k8s-stage.bringo.tel/react_api';
      case Environment.prod:
        return 'https://teleleo.com/react_api';
    }
  }

  static int get siteDomainId {
    switch (env) {
      case Environment.dev:
        return 1;
      case Environment.preprod:
        return 1;
      case Environment.prod:
        return 1;
    }
  }

  static String? get sipWebSocketUrl {
    switch (env) {
      case Environment.dev:
        return 'wss://pbx.teleleo.com:7443/';
      case Environment.preprod:
        return 'wss://pbx-pp.teleleo.com:7443/';
      case Environment.prod:
        return 'wss://pbx.teleleo.com:7443/';
    }
  }
}
