#!/usr/bin/env bash
source defer.sh

work() {
    local resource="db-handle"
    defer "echo released $resource" EXIT
    defer "echo cleanup-second" EXIT
    defer "echo cleanup-first" EXIT
    echo "acquired $resource"
}

work
echo "done"
