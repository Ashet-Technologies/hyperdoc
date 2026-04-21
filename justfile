default: build test

build:
  zig-0.16.0 build -freference-trace=11 --prominent-compile-errors

test:
  zig-0.16.0 build -freference-trace=11 --prominent-compile-errors test

dump: build   
  ./zig-out/bin/hyperdoc --format dump "test/accept/workset.hdoc"
