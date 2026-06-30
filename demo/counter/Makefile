EXEC ?= counter

BUILD_DIR ?= build
SRC_DIRS ?= src

# Build with the Homebrew GNU toolchain rather than Apple clang.
CXX := g++-16

SRCS := $(shell find $(SRC_DIRS) -name *.cpp)
OBJS := $(SRCS:%=$(BUILD_DIR)/%.o)
DEPS := $(OBJS:.o=.d)

CPPFLAGS ?= -MMD -MP
# boost::program_options is linked from our OWN g++-16 (libstdc++) build of it -- the
# Homebrew libboost_program_options.a is clang/libc++ and is ABI-incompatible with g++.
# gmp/gmpxx are C-ABI (fine) and come from Homebrew (-L/opt/homebrew/lib).
LIBS := ../../build/libd4.a ../../3rdParty/boost_po/libboost_program_options.a -L/opt/homebrew/lib -lz -lgmpxx -lgmp
INCLUDES := -I../../ -I/opt/homebrew/include

c: $(BUILD_DIR)/$(EXEC)
p: $(BUILD_DIR)/$(EXEC)_profile
d: $(BUILD_DIR)/$(EXEC)_debug
s: $(BUILD_DIR)/$(EXEC)_static

$(BUILD_DIR)/$(EXEC): CFLAGS += -O3
$(BUILD_DIR)/$(EXEC)_profile: CFLAGS += -O2 -pg
$(BUILD_DIR)/$(EXEC)_debug: CFLAGS += -O2 -g
$(BUILD_DIR)/$(EXEC)_static: CFLAGS += -O3 -DNDEBUG

$(BUILD_DIR)/$(EXEC):	LDFLAGS += 
$(BUILD_DIR)/$(EXEC)_profile:	LDFLAGS += -pg
$(BUILD_DIR)/$(EXEC)_debug:	LDFLAGS += -g
$(BUILD_DIR)/$(EXEC)_static:	LDFLAGS += -static


$(BUILD_DIR)/$(EXEC) $(BUILD_DIR)/$(EXEC)_profile $(BUILD_DIR)/$(EXEC)_debug $(BUILD_DIR)/$(EXEC)_static: $(OBJS) ../../build/libd4.a
	@echo Linking: "$@ ( $(foreach f,$^,$(subst $(BUILD_DIR)/$(SRC_DIRS),,$f)) )"	
	$(CXX) $(OBJS) -o $@ $(LDFLAGS) $(INCLUDES) $(LIBS)
	
$(BUILD_DIR)/%.cpp.o: %.cpp
	@echo Compiling: $<
	@$(MKDIR_P) $(dir $@)
	$(CXX) $(CPPFLAGS) $(CFLAGS) -c $< -o $@ $(INCLUDES)


.PHONY: clean 

clean:
	$(RM) -r $(BUILD_DIR)

-include $(DEPS)

MKDIR_P ?= mkdir -p
