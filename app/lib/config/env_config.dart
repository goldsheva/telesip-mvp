enum Environment { dev, prod }

class EnvConfig {
  static late final Environment env;

  static void init(Environment environment) {
    env = environment;
  }

  static String get baseApiUrl {
    switch (env) {
      case Environment.dev:
        return 'https://teleleo.k8s-stage.bringo.tel/react_api';
      case Environment.prod:
        return 'https://teleleo.com/react_api';
    }
  }
}
