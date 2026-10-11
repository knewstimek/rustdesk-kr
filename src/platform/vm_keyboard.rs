pub fn dispatch<F>(character: &str, usb_hid: i32, mut send: F) -> Result<bool, &'static str>
where
    F: FnMut(i32, bool),
{
    if usb_hid != -1 {
        return Ok(false);
    }
    let Some(payload) = character.strip_prefix("vm_keys:") else {
        return Ok(false);
    };
    let keys = payload
        .chars()
        .map(|key| {
            let code = key as u32;
            if code > 0x1ff || code & 0xff == 0 {
                return Err("invalid VM key code");
            }
            Ok(((code & 0xff) as i32, code & 0x100 != 0))
        })
        .collect::<Result<Vec<_>, _>>()?;
    for (key, down) in keys {
        send(key, down);
    }
    Ok(true)
}

#[cfg(feature = "flutter")]
pub fn handle(
    session: &crate::flutter::FlutterSession,
    character: &str,
    usb_hid: i32,
    lock_modes: i32,
) -> bool {
    match dispatch(character, usb_hid, |key, down| {
        if key == 0x90 {
            // LANG1 is not mapped by the pinned HID library; send the Korean scan code.
            let mut event = base::message_proto::KeyEvent::new();
            event.mode = base::message_proto::KeyboardMode::Map.into();
            event.down = down;
            event.set_chr(0xf2);
            session.send_key_event(&event);
        } else {
            session.handle_flutter_key_event("map", "", key, lock_modes, down);
        }
    }) {
        Ok(handled) => handled,
        Err(error) => {
            hbb_common::log::trace!("Invalid Android VM key packet: {}", error);
            true
        }
    }
}

#[cfg(test)]
mod tests {
    use super::dispatch;

    #[test]
    fn sends_a_complete_key_stroke_in_one_dispatch() {
        let mut sent = Vec::new();
        assert_eq!(
            dispatch("vm_keys:\u{11e}\u{1e}\u{12c}\u{2c}", -1, |key, down| sent
                .push((key, down))),
            Ok(true)
        );
        assert_eq!(
            sent,
            [(0x1e, true), (0x1e, false), (0x2c, true), (0x2c, false)]
        );
    }

    #[test]
    fn ignores_regular_events_and_rejects_a_bad_batch_without_partial_input() {
        let mut sent = Vec::new();
        assert_eq!(
            dispatch("a", 4, |key, down| sent.push((key, down))),
            Ok(false)
        );
        assert!(dispatch("vm_keys:\u{11e}\u{200}", -1, |key, down| sent
            .push((key, down)))
        .is_err());
        assert!(sent.is_empty());
    }
}
