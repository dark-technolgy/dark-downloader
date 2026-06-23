# يضمن وجود ثنائيات FFmpeg تحت bundled_ffmpeg/ قبل التثبيت — بدون خطوة يدوية منفصلة.
# يُستدعى من windows/CMakeLists.txt و linux/CMakeLists.txt
#
# يتطلب اتصالاً بالإنترنت عند أول بناء على آلة نظيفة؛ بعدها تُنسخ الملفات إلى bundled_ffmpeg/
# وتُعاد استخدامها دون تنزيل (ما لم تُحذف المجلد).

set(DARK_FFMPEG_URL_WIN
  "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
  CACHE STRING "أرشيف FFmpeg لويندوز (BtbN GPL)")

set(DARK_FFMPEG_URL_LINUX
  "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
  CACHE STRING "أرشيف FFmpeg لينكس (BtbN GPL)")

function(dark_ensure_ffmpeg_windows REPO_ROOT)
  set(_out "${REPO_ROOT}/bundled_ffmpeg/windows")
  if(EXISTS "${_out}/ffmpeg.exe")
    message(STATUS "FFmpeg (Windows): موجود مسبقاً في bundled_ffmpeg/windows")
    return()
  endif()

  message(STATUS "FFmpeg (Windows): تنزيل وفك الأرشيف إلى bundled_ffmpeg/windows …")
  file(MAKE_DIRECTORY "${_out}")

  set(_zip "${CMAKE_BINARY_DIR}/dark_ffmpeg_bootstrap_win.zip")
  set(_ext "${CMAKE_BINARY_DIR}/dark_ffmpeg_bootstrap_win_extract")

  file(REMOVE_RECURSE "${_ext}")
  file(MAKE_DIRECTORY "${_ext}")

  file(DOWNLOAD "${DARK_FFMPEG_URL_WIN}" "${_zip}" SHOW_PROGRESS STATUS _st TLS_VERIFY ON)
  if(NOT _st EQUAL 0)
    message(FATAL_ERROR "فشل تنزيل FFmpeg لويندوز (HTTP). تحقق من الشبكة أو ضع ffmpeg.exe يدوياً في bundled_ffmpeg/windows")
  endif()

  execute_process(
    COMMAND powershell -NoProfile -NonInteractive -Command
      "Expand-Archive -LiteralPath '${_zip}' -DestinationPath '${_ext}' -Force"
    RESULT_VARIABLE _ps
  )
  if(NOT _ps EQUAL 0)
    message(FATAL_ERROR "فشل فك أرشيف FFmpeg (PowerShell Expand-Archive).")
  endif()

  file(GLOB_RECURSE _ffexe "${_ext}/**/ffmpeg.exe")
  list(LENGTH _ffexe _n)
  if(_n LESS 1)
    file(GLOB_RECURSE _ffexe "${_ext}/*ffmpeg.exe")
    list(LENGTH _ffexe _n)
  endif()
  if(_n LESS 1)
    message(FATAL_ERROR "لم يُعثر على ffmpeg.exe داخل الأرشيف المُنزَّل.")
  endif()
  list(GET _ffexe 0 _main)
  get_filename_component(_bindir "${_main}" DIRECTORY)

  file(GLOB _binitems "${_bindir}/*")
  foreach(_item ${_binitems})
    get_filename_component(_base "${_item}" NAME)
    file(COPY "${_item}" DESTINATION "${_out}")
  endforeach()

  if(NOT EXISTS "${_out}/ffmpeg.exe")
    message(FATAL_ERROR "نسخ FFmpeg لويندوز فشل: لا يوجد ${_out}/ffmpeg.exe")
  endif()

  message(STATUS "FFmpeg (Windows): جاهز في ${_out}")
endfunction()

function(dark_ensure_ffmpeg_linux REPO_ROOT)
  set(_out "${REPO_ROOT}/bundled_ffmpeg/linux")
  if(EXISTS "${_out}/ffmpeg")
    message(STATUS "FFmpeg (Linux): موجود مسبقاً في bundled_ffmpeg/linux")
    return()
  endif()

  message(STATUS "FFmpeg (Linux): تنزيل وفك الأرشيف إلى bundled_ffmpeg/linux …")
  file(MAKE_DIRECTORY "${_out}")

  set(_txz "${CMAKE_BINARY_DIR}/dark_ffmpeg_bootstrap_linux.tar.xz")
  set(_ext "${CMAKE_BINARY_DIR}/dark_ffmpeg_bootstrap_linux_extract")

  file(REMOVE_RECURSE "${_ext}")
  file(MAKE_DIRECTORY "${_ext}")

  file(DOWNLOAD "${DARK_FFMPEG_URL_LINUX}" "${_txz}" SHOW_PROGRESS STATUS _st TLS_VERIFY ON)
  if(NOT _st EQUAL 0)
    message(FATAL_ERROR "فشل تنزيل FFmpeg لينكس. تحقق من الشبكة أو ضع ثنائي ffmpeg في bundled_ffmpeg/linux")
  endif()

  execute_process(
    COMMAND tar -xJf "${_txz}" -C "${_ext}"
    RESULT_VARIABLE _tr
  )
  if(NOT _tr EQUAL 0)
    message(FATAL_ERROR "فشل tar -xJf لأرشيف FFmpeg (هل xz مثبت؟).")
  endif()

  file(GLOB_RECURSE _fflist "${_ext}/**/bin/ffmpeg")
  list(LENGTH _fflist _nl)
  if(_nl LESS 1)
    file(GLOB_RECURSE _fflist "${_ext}/*/bin/ffmpeg")
    list(LENGTH _fflist _nl)
  endif()
  if(_nl LESS 1)
    file(GLOB_RECURSE _fflist "${_ext}/*bin/ffmpeg")
    list(LENGTH _fflist _nl)
  endif()
  if(_nl LESS 1)
    message(FATAL_ERROR "لم يُعثر على bin/ffmpeg داخل أرشيف لينكس.")
  endif()
  list(GET _fflist 0 _chosen)
  file(COPY "${_chosen}" DESTINATION "${_out}")
  if(NOT EXISTS "${_out}/ffmpeg")
    message(FATAL_ERROR "نسخ ffmpeg لينكس فشل.")
  endif()

  execute_process(COMMAND chmod +x "${_out}/ffmpeg" RESULT_VARIABLE _ch)
  if(NOT _ch EQUAL 0)
    message(WARNING "chmod +x على ffmpeg فشل (قد يبقى غير قابل للتنفيذ).")
  endif()

  message(STATUS "FFmpeg (Linux): جاهز في ${_out}")
endfunction()
