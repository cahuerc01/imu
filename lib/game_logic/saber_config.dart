class SaberConfig {
  // Configuración del Sable
  static double saberLength = 0.8; // Metros imaginarios del sable
  static double distanceBetweenPlayers = 1.5; // Metros asumidos entre jugadores

  // Configuración de Sensores
  static double swingThreshold =
      2.5; // Sensibilidad para detectar movimiento (swing)

  // Configuración de LEDs (Simulación)
  static int collisionFlashCount = 5; // Cuántas veces parpadea
  static int collisionFlashDurationMs = 100; // Duración de cada estado (ms)
  static int postCollisionWindowMs = 1000; // Tiempo de gracia post-colisión
}
