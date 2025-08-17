# Flutter Android PDF Reader — Pro (ไฮไลท์/โน้ต/บุ๊คมาร์ก/ซิงก์/ซูมตามนิ้ว)

ต่อยอดจากเวอร์ชันก่อน หน้านี้เป็น **Flutter App (Android)** ที่:
- จดจำหน้าล่าสุดที่อ่าน (per document)
- **ไฮไลท์/ขีดเส้นใต้/ขีดทับ/สติ๊กกี้โน้ต** ด้วย `Syncfusion SfPdfViewer`
- **บุ๊คมาร์ก** พร้อมหน้ารวมรายการ
- **ซิงก์ข้ามเครื่อง** (Firestore + Anonymous Auth) เก็บ last page, bookmarks, notes และสำรอง PDF ฉบับที่มีอนุมัติ (flattened) ลง Cloud Storage
- **ซูมอ่านบริเวณมือชี้**: ดับเบิลแท็ปเพื่อซูมเจาะจุด แล้วลากนิ้วเพื่อเลื่อนตำแหน่งอ่าน

> ใช้ Syncfusion Community License ได้หากเข้าเงื่อนไขทางการค้า/รายได้ของโครงการ

---

## pubspec.yaml (ส่วนที่สำคัญ)
```yaml
name: pdf_reader_pro
publish_to: 'none'

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  file_picker: ^8.0.0
  shared_preferences: ^2.2.2
  syncfusion_flutter_pdfviewer: ^26.2.10
  firebase_core: ^3.5.0
  firebase_auth: ^5.1.4
  cloud_firestore: ^5.4.4
  firebase_storage: ^12.3.5

flutter:
  uses-material-design: true
```

> หมายเหตุ: เวอร์ชันอาจขยับได้ตามตัวแก้ปัญหา dependency ล่าสุดของคุณ

---

## android/app/google-services.json
ตั้งค่า Firebase โปรเจกต์ของคุณแล้วดาวน์โหลดไฟล์นี้วางใน `android/app/` พร้อมเพิ่มปลั๊กอิน `com.google.gms.google-services` ตามคู่มือ Firebase Flutter

---

## lib/main.dart
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Anonymous sign-in for sync
  await FirebaseAuth.instance.signInAnonymously();
  runApp(const PDFProApp());
}

class PDFProApp extends StatelessWidget {
  const PDFProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Reader Pro',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _lastFileName;
  int? _lastPage;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastFileName = prefs.getString('last_file_name');
      _lastPage = prefs.getInt('last_page');
    });
  }

  Future<void> _openPicker() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.single;
    final data = file.bytes ?? await File(file.path!).readAsBytes();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewerPage(
          fileName: file.name,
          pdfBytes: data,
        ),
      ),
    ).then((_) => _loadLast());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Reader Pro')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('เลือกไฟล์ PDF เพื่อเริ่มอ่าน — แอพจะจำหน้า, ทำไฮไลท์/โน้ต, บุ๊คมาร์ก และซิงก์ข้ามเครื่อง'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openPicker,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('เปิดไฟล์ PDF'),
            ),
            const SizedBox(height: 24),
            if (_lastFileName != null && _lastPage != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(_lastFileName!),
                  subtitle: Text('ค้างที่หน้า $_lastPage'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ViewerPage extends StatefulWidget {
  final String fileName;
  final Uint8List pdfBytes;
  const ViewerPage({super.key, required this.fileName, required this.pdfBytes});
  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfKey = GlobalKey();
  double _targetZoom = 1.0;
  Offset? _lastTapLocal; // for zoom-to-point

  late final String _docId; // key for sync storage

  @override
  void initState() {
    super.initState();
    _docId = _stableDocId(widget.pdfBytes, widget.fileName);
  }

  // A stable ID per document (size + first 64KB hash + name)
  String _stableDocId(Uint8List bytes, String name) {
    final firstChunk = bytes.sublist(0, bytes.length < 65536 ? bytes.length : 65536);
    final h = firstChunk.fold<int>(0, (p, c) => (p * 131 + c) & 0x7fffffff);
    return 'v2::$h::${bytes.length}::$name';
  }

  Future<void> _saveLocalSession(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_page', page);
    await prefs.setString('last_file_name', widget.fileName);
  }

  // ---------- Cloud Sync (Firestore) ----------
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('pdf_sessions');

  Future<void> _syncLastPage(int page) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _col.doc('${uid}__$docId').set({
      'uid': uid,
      'docId': _docId,
      'fileName': widget.fileName,
      'lastPage': page,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _addBookmark() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final page = _controller.pageNumber;
    final title = await _prompt(context, 'ชื่อบุ๊คมาร์ก', hint: 'เช่น บทที่ 2');
    if (title == null) return;
    await _col.doc('${uid}__$docId').collection('bookmarks').add({
      'page': page,
      'title': title,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกบุ๊คมาร์กที่หน้า $page')));
    }
  }

  Future<void> _showBookmarks() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col.doc('${uid}__$docId').collection('bookmarks').orderBy('createdAt', descending: true).snapshots(),
        builder: (c, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('ยังไม่มีบุ๊คมาร์ก'));
          return ListView(
            children: [
              for (final d in docs)
                ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: Text(d['title'] ?? 'bookmark'),
                  subtitle: Text('หน้า ${d['page']}'),
                  onTap: () {
                    Navigator.pop(context);
                    _controller.jumpToPage(d['page']);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => d.reference.delete(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------- Notes via Sticky Note annotation ----------
  Future<void> _addStickyNoteAtSelection() async {
    final state = _pdfKey.currentState;
    if (state == null) return;
    final lines = state.getSelectedTextLines();
    if (lines == null || lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('โปรดเลือกข้อความก่อน')));
      return;
    }
    final content = await _prompt(context, 'จดโน้ต', hint: 'พิมพ์โน้ตที่นี่');
    if (content == null) return;
    // Add sticky note at the first selected line bounds center
    final first = lines.first.bounds.first;
    final note = StickyNoteAnnotation(
      pageNumber: lines.first.pageNumber,
      bounds: Rect.fromLTWH(first.left, first.top, 24, 24),
      text: content,
    );
    _controller.addAnnotation(note);
  }

  // ---------- Highlight from selection ----------
  void _highlightSelection() {
    final state = _pdfKey.currentState;
    final lines = state?.getSelectedTextLines();
    if (lines == null || lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('โปรดเลือกข้อความก่อน')));
      return;
    }
    final ann = HighlightAnnotation(textBoundsCollection: lines);
    _controller.addAnnotation(ann);
    _controller.clearSelection();
  }

  // ---------- Export/Import annotations to Cloud Storage ----------
  Future<void> _exportAnnotatedPDF() async {
    // Save current PDF (with annotations) and upload
    final bytes = await _controller.saveDocument();
    final ref = FirebaseStorage.instance.ref().child('pdf_annotated/$_docId.pdf');
    await ref.putData(Uint8List.fromList(bytes));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อัปโหลด PDF ที่บันทึกอนุมัติแล้ว')));
    }
  }

  // ---------- Zoom to finger (double-tap) ----------
  void _handleDoubleTapDown(TapDownDetails d) {
    _lastTapLocal = d.localPosition;
  }

  void _handleDoubleTap() {
    // Toggle zoom between 1.0 and 2.5 centered near last tap
    _targetZoom = (_controller.zoomLevel < 2.0) ? 2.5 : 1.0;
    _controller.zoomLevel = _targetZoom;
    // Nudge scroll so tapped point stays roughly at center
    final tap = _lastTapLocal;
    if (tap != null) {
      final viewport = MediaQuery.of(context).size;
      final dx = (tap.dx - viewport.width / 2);
      final dy = (tap.dy - viewport.height / 2);
      final o = _controller.scrollOffset;
      _controller.jumpTo(xOffset: (o.dx + dx).clamp(0, double.infinity), yOffset: (o.dy + dy).clamp(0, double.infinity));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.fileName}')),
      body: GestureDetector(
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        child: SfPdfViewer.memory(
          widget.pdfBytes,
          key: _pdfKey,
          controller: _controller,
          maxZoomLevel: 5,
          canShowScrollHead: true,
          canShowPaginationDialog: true,
          onDocumentLoaded: (details) async {
            final prefs = await SharedPreferences.getInstance();
            final page = prefs.getInt('last_page') ?? 1;
            _controller.jumpToPage(page);
          },
          onPageChanged: (d) {
            _saveLocalSession(d.newPageNumber);
            _syncLastPage(d.newPageNumber);
          },
          onTextSelectionChanged: (details) {
            // custom quick actions
            if (details.selectedText == null || details.selectedText!.isEmpty) return;
            final overlay = Overlay.of(context);
            final overlayEntry = OverlayEntry(
              builder: (_) => Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Wrap(spacing: 8, children: [
                      TextButton.icon(onPressed: () { _highlightSelection(); overlayEntry.remove(); }, icon: const Icon(Icons.highlight), label: const Text('ไฮไลท์')),
                      TextButton.icon(onPressed: () { _addStickyNoteAtSelection(); overlayEntry.remove(); }, icon: const Icon(Icons.sticky_note_2_outlined), label: const Text('จดโน้ต')),
                      TextButton.icon(onPressed: () { _controller.clearSelection(); overlayEntry.remove(); }, icon: const Icon(Icons.close), label: const Text('ยกเลิก')),
                    ]),
                  ),
                ),
              ),
            );
            overlay.insert(overlayEntry);
          },
          onAnnotationAdded: (ann) {
            // Could mirror to Firestore ifต้องการ: serialize minimal fields
          },
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'bm',
            onPressed: _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('บุ๊คมาร์ก'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'list',
            onPressed: _showBookmarks,
            icon: const Icon(Icons.list_alt),
            label: const Text('รายการ'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'export',
            onPressed: _exportAnnotatedPDF,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('สำรองขึ้นคลาวด์'),
          ),
        ],
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, {String? hint}) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()), child: const Text('ตกลง')),
      ],
    ),
  );
}
```

---

### วิธีรัน/บิลด์
```bash
flutter pub get
flutter run -d android
# บิลด์ APK
flutter build apk --release
```

### โครงสร้างซิงก์ (ตัวอย่าง)
- Firestore: `pdf_sessions/{uid__docId}` เก็บ `lastPage, fileName, updatedAt`
- Firestore subcollection: `pdf_sessions/{...}/bookmarks` เก็บ `page, title`
- Cloud Storage: `pdf_annotated/{docId}.pdf` เป็นไฟล์ PDF ที่กด “สำรองขึ้นคลาวด์” แล้ว (รวมอนุมัติ)

### เคล็ดลับ
- **Annotation API**: `PdfViewerController.addAnnotation(...)`, `getAnnotations()`, `removeAnnotation(...)`, `onAnnotationAdded/Edited/Removed` (ดูรายละเอียดในเอกสาร Syncfusion)
- **ซูมตามนิ้ว**: ใช้ `onDoubleTapDown` จับพิกัด + `zoomLevel` และ `jumpTo(xOffset, yOffset)` เพื่อพา viewport ไปยังจุดแตะ
- ถ้าต้องการ **export/import เฉพาะข้อมูลอนุมัติ (JSON/FDF/XFDF)** สามารถใช้ `syncfusion_flutter_pdf` เพื่อ export/import annotations แล้วเก็บเป็นไฟล์ JSON/บันทึกใน Firestore ได้

---

## CI: GitHub Actions — one‑click สร้าง APK
สร้างไฟล์ไว้ที่ `.github/workflows/build-android.yml`
```yaml
name: Build Android APK

on:
  workflow_dispatch:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Flutter version
        run: flutter --version

      # ถ้าโปรเจกต์ใช้ Firebase ให้ใส่ secret FIREBASE_JSON_BASE64
      - name: Decode google-services.json
        if: ${{ secrets.FIREBASE_JSON_BASE64 != '' }}
        run: |
          mkdir -p android/app
          echo "$FIREBASE_JSON_BASE64" | base64 -d > android/app/google-services.json
        env:
          FIREBASE_JSON_BASE64: ${{ secrets.FIREBASE_JSON_BASE64 }}

      # เซ็นแอปแบบ release — สร้าง key.properties จาก secrets
      - name: Prepare keystore
        if: ${{ secrets.ANDROID_KEYSTORE_BASE64 != '' }}
        run: |
          mkdir -p $HOME/keystores
          echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > $HOME/keystores/upload.jks
          cat <<EOF > android/key.properties
          storePassword=${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          keyPassword=${{ secrets.ANDROID_KEY_ALIAS_PASSWORD }}
          keyAlias=${{ secrets.ANDROID_KEY_ALIAS }}
          storeFile=$HOME/keystores/upload.jks
          EOF
        env:
          ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}

      - name: Pub get
        run: flutter pub get

      - name: Build APK (release, split per ABI)
        run: flutter build apk --release --split-per-abi

      - name: Upload APKs
        uses: actions/upload-artifact@v4
        with:
          name: apk
          path: build/app/outputs/flutter-apk/*.apk
```

### Secrets ที่ต้องใส่ใน GitHub → Settings → Secrets → Actions
- `FIREBASE_JSON_BASE64` : ไฟล์ `android/app/google-services.json` เข้ารหัส base64 (สำหรับซิงก์/แจ้งเตือนของ Firebase)
- `ANDROID_KEYSTORE_BASE64` : ไฟล์ `.jks` ที่เข้ารหัส base64 (สำหรับเซ็น APK)
- `ANDROID_KEYSTORE_PASSWORD` : รหัส keystore
- `ANDROID_KEY_ALIAS` : ชื่อ alias (เช่น `upload`)
- `ANDROID_KEY_ALIAS_PASSWORD` : รหัส alias

> ถ้ายังไม่มี keystore: สร้างด้วย `keytool -genkeypair ...` แล้ว `base64 -w0 upload.jks > keystore.b64` เพื่อนำค่าไปวางใน Secret

### หมายเหตุ
- ถ้าไม่ตั้งค่า secrets การ build จะยังสำเร็จเป็น **debug APK** ได้: เปลี่ยน step build เป็น `flutter build apk --debug` หรือแค่ใช้ `flutter run` ในเครื่องคุณ
- ตรวจให้ `applicationId` ใน `android/app/build.gradle` ตรงกับที่สร้างแอปใน Firebase
- ต้องเพิ่ม/เรียก `SyncfusionLicense.registerLicense('YOUR_KEY')` ใน `main()` ถ้าใช้เวอร์ชันที่ต้องลงทะเบียนไลเซนส์
