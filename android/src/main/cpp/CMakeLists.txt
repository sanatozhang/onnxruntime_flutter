cmake_minimum_required(VERSION 3.18.1)
project("onnxruntime")

# NOTE: libonnxruntime.so is prebuilt and must be 16KB-aligned at link time.
# Do not add linker flags to compile flags here; rebuild the library using the
# provided build_onnxruntime_16kb.sh script instead.

# 查找预编译的 ONNX Runtime 库（作为后备）
set(ONNXRUNTIME_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libonnxruntime.so")

if(EXISTS ${ONNXRUNTIME_LIB_PATH})
    # 如果预编译库存在，导入它
    add_library(onnxruntime_imported SHARED IMPORTED)
    set_target_properties(onnxruntime_imported PROPERTIES
        IMPORTED_LOCATION ${ONNXRUNTIME_LIB_PATH}
    )
    
    # 创建一个包装库，使用 16KB 对齐标志重新链接
    # 注意：这不会改变预编译库本身的对齐，但会创建一个新的包装库
    add_library(onnxruntime SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/.gitkeep
    )
    
    # 链接到预编译的 onnxruntime 库
    target_link_libraries(onnxruntime PRIVATE onnxruntime_imported)
    
    # 设置输出名称
    set_target_properties(onnxruntime PROPERTIES
        OUTPUT_NAME "onnxruntime"
        PREFIX "lib"
    )
    
    message(STATUS "Using precompiled ONNX Runtime library from ${ONNXRUNTIME_LIB_PATH}")
    message(WARNING "Precompiled library may not be 16KB aligned. Consider rebuilding from source.")
else()
    message(FATAL_ERROR "ONNX Runtime library not found at ${ONNXRUNTIME_LIB_PATH}. Please ensure the library exists or configure CMake to build from source.")
endif()
