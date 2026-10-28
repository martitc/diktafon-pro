import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'services/providers/chatgpt/chatgpt_connection_probe.dart';
import 'services/providers/chatgpt/loopback_authorization.dart';
import 'services/providers/gemini/gemini_connection_probe.dart';

/// Isolated T001 diagnostic, built with the `.cloudprobe` application ID.
/// Account credentials and the API key stay in memory for this probe only.
void main() => runApp(const MaterialApp(home: CloudConnectionProbe()));

class CloudConnectionProbe extends StatefulWidget {
  const CloudConnectionProbe({super.key});

  @override
  State<CloudConnectionProbe> createState() => _CloudConnectionProbeState();
}

class _CloudConnectionProbeState extends State<CloudConnectionProbe> {
  LoopbackAuthorization? _attempt;
  final _key = TextEditingController();
  final _model = TextEditingController(text: 'gemini-3.8-flash');
  final _instructions = TextEditingController();
  XFile? _audio;
  bool _running = false;
  String _status = 'Prueba local con datos ficticios. No conecta una cuenta.';
  String _chatStatus =
      'La prueba comprueba el acceso y cierra la sesión al terminar.';
  String _geminiStatus =
      'Elige una muestra breve y tu modelo disponible en Gemini.';
  String? _transcript;

  Future<void> _probe() async {
    setState(() {
      _running = true;
      _status =
          'Esperando el retorno del navegador. Vuelve aquí tras la prueba.';
    });
    await _saveResult('loopback', false);
    LoopbackAuthorization? attempt;
    try {
      attempt = await LoopbackAuthorization.start();
      if (!mounted) return;
      setState(() => _attempt = attempt);
      // Attach a handler before browser launch: timeout/cancel can occur during it.
      final outcome = attempt.result.then<bool>(
        (value) =>
            value.code == 'probe_code' && value.clientId == 'probe_client',
        onError: (Object _) => false,
      );
      final opened = await launchUrl(
        attempt.redirectUri.replace(
          queryParameters: {
            'state': attempt.state,
            'code': 'probe_code',
            'client_id': 'probe_client',
          },
        ),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        if (mounted) setState(() => _status = 'No se pudo abrir el navegador.');
        return;
      }
      final success = await outcome;
      await _saveResult('loopback', success);
      if (mounted) {
        setState(
          () => _status = success
              ? 'Éxito: el navegador ha devuelto la prueba local a la app.'
              : 'Error: no se ha recibido un retorno válido. Puedes reintentar.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _status = 'Error al iniciar la prueba local. Puedes reintentar.',
        );
      }
    } finally {
      await attempt?.dispose();
      if (identical(_attempt, attempt)) _attempt = null;
      if (mounted) setState(() => _running = false);
    }
  }

  Future<String> _hostId() async {
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/connection-probe-host-id');
    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      if (RegExp(r'^urn:uuid:[0-9a-f-]{36}$').hasMatch(value)) return value;
    }
    final value = 'urn:uuid:${const Uuid().v4()}';
    await directory.create(recursive: true);
    await file.writeAsString(value, flush: true);
    return value;
  }

  // Local development evidence only: never store credentials or audio content.
  Future<void> _saveResult(
    String check,
    bool passed, {
    int? count,
    bool? luna,
  }) async {
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      final file = File('${directory.path}/connection-probe-results.json');
      final results = await file.exists()
          ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
          : <String, dynamic>{};
      results[check] = {
        'passed': passed,
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
        'count': ?count,
        'lunaAvailable': ?luna,
      };
      final staging = File('${file.path}.tmp');
      await staging.writeAsString(jsonEncode(results), flush: true);
      await staging.rename(file.path);
    } catch (_) {
      // A diagnostic report must not prevent session cleanup.
    }
  }

  Future<void> _probeChatGpt() async {
    setState(() {
      _running = true;
      _chatStatus =
          'Inicia sesión en el navegador y autoriza el uso del plan ChatGPT.';
    });
    await _saveResult('chatgpt', false);
    final api = ChatGptConnectionProbe();
    LoopbackAuthorization? attempt;
    ProbeTokenSet? tokens;
    var result = 'La conexión no se ha completado. Puedes reintentar.';
    var revoked = true;
    var passed = false;
    int? modelCount;
    bool? lunaAvailable;
    try {
      final hostId = await _hostId();
      attempt = await LoopbackAuthorization.start();
      if (!mounted) return;
      setState(() => _attempt = attempt);
      final outcome = attempt.result.then<AuthorizationCode?>(
        (value) => value,
        onError: (Object _) => null,
      );
      if (!mounted) return;
      final opened = await launchUrl(
        attempt.authorizationUri(
          hostId: hostId,
          agentName: 'Diktafon Pro Conexiones',
        ),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) return;
      final authorization = await outcome;
      if (authorization == null) return;
      _attempt = null;
      if (mounted) {
        setState(
          () => _chatStatus = 'Verificando cuenta y modelos disponibles…',
        );
      }
      tokens = await api.exchangeCode(
        code: authorization.code,
        clientId: authorization.clientId,
        codeVerifier: attempt.codeVerifier,
        redirectUri: attempt.redirectUri,
        nonce: attempt.nonce,
      );
      final models = await api.listModels(tokens);
      tokens = await api.refresh(tokens);
      await api.listModels(tokens);
      final luna = models.any(
        (model) => model.slug.toLowerCase().contains('luna'),
      );
      modelCount = models.length;
      lunaAvailable = luna;
      passed = true;
      result =
          'Conexión y renovación correctas. ${models.length} modelos disponibles. '
          '${luna ? 'Luna aparece en tu catálogo.' : 'Luna no aparece en tu catálogo.'}\n'
          '${models.map((model) => model.displayName).join(', ')}';
    } on ProbeException catch (error) {
      if (error.remoteCleanupUnconfirmed) revoked = false;
      result = error.code == 'planPermissionMissing'
          ? 'La cuenta no ha autorizado el uso del plan ChatGPT.'
          : 'No se pudo verificar la conexión con ChatGPT. Puedes reintentar.';
    } catch (_) {
      result = 'No se pudo completar la conexión. Puedes reintentar.';
    } finally {
      if (tokens != null) {
        try {
          await api.revoke(tokens);
        } catch (_) {
          revoked = false;
        }
      }
      api.close();
      await attempt?.dispose();
      await _saveResult(
        'chatgpt',
        passed && revoked,
        count: modelCount,
        luna: lunaAvailable,
      );
      if (identical(_attempt, attempt)) _attempt = null;
      if (mounted) {
        setState(() {
          _running = false;
          final cleanup = !revoked
              ? 'No se confirmó el cierre remoto. Desconecta Diktafon Pro Conexiones en los ajustes de ChatGPT.'
              : tokens == null
              ? 'La prueba no ha guardado credenciales.'
              : 'La sesión de prueba está cerrada.';
          _chatStatus = '$result\n$cleanup';
        });
      }
    }
  }

  Future<void> _chooseAudio() async {
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Audio',
          extensions: [
            'wav',
            'mp3',
            'm4a',
            'aac',
            'ogg',
            'oga',
            'flac',
            'webm',
            'opus',
          ],
          mimeTypes: ['audio/*'],
          uniformTypeIdentifiers: ['public.audio'],
        ),
      ],
    );
    if (selected != null && mounted) setState(() => _audio = selected);
  }

  Future<void> _probeGemini() async {
    final audio = _audio;
    if (audio == null) return;
    setState(() {
      _running = true;
      _transcript = null;
      _geminiStatus = 'Enviando el audio seleccionado a Google Gemini…';
    });
    await _saveResult('gemini', false);
    final client = HttpClient();
    try {
      if (await audio.length() >= 14000000) {
        if (mounted) {
          setState(
            () => _geminiStatus =
                'Esta prueba admite muestras de menos de 14 MB. Selecciona un audio más corto.',
          );
        }
        return;
      }
      const types = {
        'wav': 'audio/wav',
        'mp3': 'audio/mp3',
        'm4a': 'audio/m4a',
        'aac': 'audio/aac',
        'ogg': 'audio/ogg',
        'oga': 'audio/ogg',
        'flac': 'audio/flac',
        'webm': 'audio/webm',
        'opus': 'audio/opus',
      };
      final mime = types[audio.name.split('.').last.toLowerCase()];
      if (mime == null) {
        if (mounted) {
          setState(
            () => _geminiStatus =
                'Formato de audio no compatible con esta prueba.',
          );
        }
        return;
      }
      final transcript = await GeminiConnectionProbe(client: client).transcribe(
        audioBytes: await audio.readAsBytes(),
        mimeType: mime,
        apiKey: _key.text.trim(),
        model: _model.text.trim(),
        instructions: _instructions.text.trim(),
      );
      final count = transcript.segments.fold<int>(
        0,
        (total, segment) => total + segment.words.length,
      );
      await _saveResult('gemini', true, count: count);
      if (mounted) {
        setState(() {
          _geminiStatus =
              'Gemini ha devuelto $count palabras con tiempos válidos. Idioma: ${transcript.languageCode}.';
          final sample = transcript.segments
              .expand((segment) => segment.words)
              .take(12)
              .map(
                (word) =>
                    '${(word.startMs / 1000).toStringAsFixed(2)}–${(word.endMs / 1000).toStringAsFixed(2)} s: ${word.text}',
              )
              .join('\n');
          _transcript =
              '${transcript.plainText}\n\nMuestra de tiempos:\n$sample';
        });
      }
    } on GeminiProbeException catch (error) {
      await _saveResult('gemini', false);
      if (mounted) {
        setState(
          () => _geminiStatus = switch (error.kind) {
            GeminiProbeFailure.configuration =>
              'Añade tu clave y el nombre de un modelo disponible en tu cuenta.',
            GeminiProbeFailure.http =>
              'Gemini rechazó la solicitud (HTTP ${error.statusCode}). Revisa la clave, el modelo y la cuota.',
            GeminiProbeFailure.requestTooLarge =>
              'La muestra supera el tamaño permitido para esta prueba.',
            GeminiProbeFailure.invalidResponse =>
              'La respuesta no contiene una transcripción con tiempos válidos.',
            GeminiProbeFailure.timeout =>
              'Gemini tardó demasiado en responder. Prueba con una muestra más corta o con otra conexión.',
            GeminiProbeFailure.transport =>
              'No se pudo conectar con Gemini. Comprueba Internet y vuelve a intentarlo.',
            _ =>
              'No se pudo procesar esta muestra. Revisa la conexión y el audio.',
          },
        );
      }
    } catch (_) {
      await _saveResult('gemini', false);
      if (mounted) {
        setState(
          () =>
              _geminiStatus = 'No se pudo leer o enviar el audio seleccionado.',
        );
      }
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    unawaited(_attempt?.dispose());
    _key.dispose();
    _model.dispose();
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Prueba de conexiones')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('1. Retorno del navegador', style: TextStyle(fontSize: 20)),
        Text(_status, key: const ValueKey('probe-status')),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _running ? null : _probe,
          child: const Text('Probar retorno del navegador'),
        ),
        if (_attempt != null)
          TextButton(
            onPressed: () => _attempt?.dispose(),
            child: const Text('Cancelar prueba'),
          ),
        const Divider(height: 40),
        const Text('2. Cuenta ChatGPT', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 12),
        Text(_chatStatus, key: const ValueKey('chatgpt-status')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _running ? null : _probeChatGpt,
          child: const Text('Comprobar ChatGPT'),
        ),
        const Divider(height: 40),
        const Text('3. Transcripción Gemini', style: TextStyle(fontSize: 20)),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !_running,
          decoration: const InputDecoration(labelText: 'Tu clave API Gemini'),
        ),
        TextField(
          controller: _model,
          enabled: !_running,
          decoration: const InputDecoration(labelText: 'Modelo Gemini'),
        ),
        TextField(
          controller: _instructions,
          enabled: !_running,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Instrucciones de transcripción (opcional)',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _running ? null : _chooseAudio,
          child: Text(_audio?.name ?? 'Seleccionar muestra de audio'),
        ),
        const Text(
          'Al pulsar «Enviar muestra a Gemini», el audio seleccionado se envía a Google. La clave solo se mantiene mientras esta pantalla está abierta.',
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _running || _audio == null ? null : _probeGemini,
          child: const Text('Enviar muestra a Gemini'),
        ),
        const SizedBox(height: 12),
        Text(_geminiStatus, key: const ValueKey('gemini-status')),
        if (_transcript != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SelectableText(_transcript!),
          ),
        if (_running)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );
}
