import Darwin
import Foundation

/// One entry returned by a directory listing. Metadata only: contents are never read,
/// so iCloud dataless placeholders are not downloaded.
public struct DirEntry: Sendable {
    public var name: String
    public var isDir: Bool
    public var isSymlink: Bool
    public var device: Int32
    public var inode: UInt64
    public var linkCount: UInt32
    public var allocatedBytes: UInt64
    public var modified: Int64
}

public enum ReadError: Error, Equatable {
    case denied
    case failed(Int32)
}

/// Lists one directory with `getattrlistbulk(2)`, falling back to `lstat` per entry.
public enum DirectoryReader {
    public static func read(_ path: String) -> Result<[DirEntry], ReadError> {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { return .failure(errnoError()) }
        defer { close(fd) }
        if let entries = bulkRead(fd: fd) { return .success(entries) }
        return fallbackRead(path)
    }

    static func errnoError() -> ReadError {
        (errno == EACCES || errno == EPERM) ? .denied : .failed(errno)
    }

    // Buffer layout per entry (see getattrlistbulk(2)): length, returned attrs, error,
    // name, devid, objtype, modtime, fileid, then file attrs linkcount, allocsize.
    static func bulkRead(fd: Int32) -> [DirEntry]? {
        var req = attrlist()
        req.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        req.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_ERROR)
            | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID)
        req.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let bufSize = 256 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 16)
        defer { buf.deallocate() }
        var out: [DirEntry] = []

        while true {
            let count = getattrlistbulk(fd, &req, buf, bufSize, 0)
            if count < 0 { return out.isEmpty ? nil : out }
            if count == 0 { return out }
            var entry = buf
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                var p = entry + 4
                let returned = p.loadUnaligned(as: attribute_set_t.self)
                p += MemoryLayout<attribute_set_t>.size
                defer { entry += length }

                if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                    let err = p.loadUnaligned(as: UInt32.self)
                    p += 4
                    if err != 0 { continue }
                }
                var e = DirEntry(name: "", isDir: false, isSymlink: false, device: 0, inode: 0,
                                 linkCount: 1, allocatedBytes: 0, modified: 0)
                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let ref = p.loadUnaligned(as: attrreference_t.self)
                    e.name = String(cString: (p + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    p += MemoryLayout<attrreference_t>.size
                }
                if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                    e.device = p.loadUnaligned(as: dev_t.self)
                    p += MemoryLayout<dev_t>.size
                }
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    let type = p.loadUnaligned(as: fsobj_type_t.self)
                    e.isDir = type == VDIR.rawValue
                    e.isSymlink = type == VLNK.rawValue
                    p += MemoryLayout<fsobj_type_t>.size
                }
                if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                    e.modified = Int64(p.loadUnaligned(as: timespec.self).tv_sec)
                    p += MemoryLayout<timespec>.size
                }
                if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                    e.inode = p.loadUnaligned(as: UInt64.self)
                    p += 8
                }
                if !e.isDir {
                    if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                        e.linkCount = p.loadUnaligned(as: UInt32.self)
                        p += 4
                    }
                    if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                        e.allocatedBytes = UInt64(max(0, p.loadUnaligned(as: off_t.self)))
                        p += 8
                    }
                }
                out.append(e)
            }
        }
    }

    static func fallbackRead(_ path: String) -> Result<[DirEntry], ReadError> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return .failure(errnoError())
        }
        var out: [DirEntry] = []
        out.reserveCapacity(names.count)
        for name in names {
            var st = stat()
            guard lstat(path + "/" + name, &st) == 0 else { continue }
            let type = st.st_mode & S_IFMT
            out.append(DirEntry(name: name, isDir: type == S_IFDIR, isSymlink: type == S_IFLNK,
                                device: st.st_dev, inode: st.st_ino, linkCount: UInt32(st.st_nlink),
                                allocatedBytes: UInt64(st.st_blocks) * 512, modified: Int64(st.st_mtimespec.tv_sec)))
        }
        return .success(out)
    }
}
