package ru.milionchik.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge-to-edge с первого кадра: окно рисуется под статус-баром и жестовой
        // панелью, отступы учитывает Flutter (MediaQuery.padding). minSdk 30,
        // поэтому хватает API платформы, androidx не нужен.
        window.setDecorFitsSystemWindows(false)
        super.onCreate(savedInstanceState)
    }
}
