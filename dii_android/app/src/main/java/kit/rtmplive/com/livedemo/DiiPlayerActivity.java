package kit.rtmplive.com.livedemo;
import android.app.Activity;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.Environment;
import android.view.View;

import org.dii.core.DiiMediaCore;
import org.dii.core.DiiPlayer;
import org.dii.core.IDiiPlayerHelper;
import org.dii.webrtc.SurfaceViewRenderer;
import org.dii.webrtc.VideoRenderer;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;

public class DiiPlayerActivity extends Activity  {
    private SurfaceViewRenderer mRenderView = null;
    private VideoRenderer mVideoRender = null;
    private  String file_or_url;
    private DiiPlayer dii_player;
    private boolean mute_ = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_dii_player);

        mRenderView = (SurfaceViewRenderer) findViewById(R.id.render_view);
        mRenderView.init(DiiMediaCore.Inst().Egl().getEglBaseContext(), null);

//        file_or_url = "http://eccp-kejian.koolearn.com/246c43a06d244725b4cba91f9cde4dde/353b00ead463480db26333855d57d213-278a6cda960a99ccbef74867f4123a9b-fd.m3u8";
        file_or_url = "rtmp://ali.fifo.site/live/demo";
        file_or_url = "rtmp://112.74.184.110/live/seaworld";
        String sdcard_path = Environment.getExternalStorageDirectory().toString();
        DiiMediaCore.Inst().SetTraceLog(sdcard_path + "/dii_media_kit.log", DiiMediaCore.LOG_INFO);
        DiiMediaCore.Inst().SetLogToDebug(DiiMediaCore.LOG_INFO);
        mVideoRender = new VideoRenderer(mRenderView);
        dii_player = new DiiPlayer(this, mVideoRender.GetRenderPointer());
        dii_player.setPlayerCallbck(new IDiiPlayerHelper.IDiiPlayerCallback() {
            @Override
            public void OnPlayerState(int state, int code) {
                switch (state) {
                    case DiiPlayer.STATE_ERROR:
                        break;
                    case DiiPlayer.STATE_PLAYING:
                        break;
                    case DiiPlayer.STATE_STOPPED:
                        break;
                    case DiiPlayer.STATE_PAUSED:
                        break;
                    case DiiPlayer.STATE_SEEKING:
                        break;
                    case DiiPlayer.STATE_BUFFERING:
                        break;
                    case DiiPlayer.STATE_STUCK:
                        break;
                    case DiiPlayer.STATE_FINISH:
                        break;
                    default:
                        break;
                }
            }

            @Override
            public void OnStreamSyncTs(long ts) {
                // rtmp ???????????????
            }

            @Override
            public void OnResolutionChange(int height, int width) {
                // ???????????????
            }

            @Override
            public void OnStatistics(String json) {
                // ???????????????
            }
        });
    }

    @Override
    protected void onDestroy() {
        dii_player.destroy();
        super.onDestroy();
    }

    /**
     * the button click event listener
     *
     * @param btn
     */
    public void OnBtnClicked(View btn) {
        if (btn.getId() == R.id.btn_start) {
            dii_player.start(file_or_url);
        } else if (btn.getId() == R.id.btn_pause) {
            dii_player.pause();
        } else if (btn.getId() == R.id.btn_resume) {
            dii_player.resume();
        } else if (btn.getId() == R.id.btn_stop) {
            dii_player.stop();
        } else if(btn.getId() == R.id.btn_mute) {
            mute_ = !mute_;
            dii_player.setMute(mute_);
        }  else if (btn.getId() == R.id.btn_snap) {
            mRenderView.getBitmapFrame(new SurfaceViewRenderer.Helper() {
                @Override
                public void onFrame(Bitmap bmp) {
                    Bitmap bitmap = bmp;
                    if (bitmap != null) {
                        // ????????????SD?????????
                        String sdCardPath = Environment.getExternalStorageDirectory().getPath();
                        // ??????????????????
                        String filePath = sdCardPath + File.separator + "pixpark.png";
                        BufferedOutputStream bos = null;
                        try {
                            bos = new BufferedOutputStream(new FileOutputStream(filePath));

                            bitmap.compress(Bitmap.CompressFormat.JPEG, 100, bos);
                            bitmap.recycle();
                        } catch (FileNotFoundException e) {
                            e.printStackTrace();
                        } finally {
                            if (bos != null) try {
                                bos.close();
                            } catch (IOException e) {
                                e.printStackTrace();
                            }
                        }
                    }
                }
            });

        }
    }
}
